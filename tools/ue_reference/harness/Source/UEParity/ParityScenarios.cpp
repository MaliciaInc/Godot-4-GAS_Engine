#include "ParityScenarios.h"

#include "AbilitySystemComponent.h"
#include "AbilitySystemGlobals.h"
#include "AbilitySystemTestAttributeSet.h"
#include "Dom/JsonObject.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Misc/ScopeExit.h"
#include "GameFramework/Actor.h"
#include "ParityActor.h"
#include "GameplayEffect.h"
#include "GameplayEffectTypes.h"
#include "GameplayTagsManager.h"
#include "Misc/FileHelper.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

DEFINE_LOG_CATEGORY_STATIC(LogParity, Display, All);

namespace ParityRun
{
/** "attack" and "health" in the goldens, on the set the plugin already ships. */
const TCHAR* AttackName = TEXT("Strength");
const TCHAR* HealthName = TEXT("PhysicalDamage");

FGameplayAttribute Attribute(const TCHAR* Named)
{
	return FGameplayAttribute(
		FindFProperty<FProperty>(UAbilitySystemTestAttributeSet::StaticClass(), Named));
}

/** A component with nothing on it. Five scenarios sharing one character compose
 *  on top of each other, and the fifth then reads as a measurement. */
UAbilitySystemComponent* Fresh(UWorld* World)
{
	AParityActor* Carrier = World->SpawnActor<AParityActor>();
	UAbilitySystemComponent* Asc = Carrier->GetAbilitySystemComponent();
	Asc->InitAbilityActorInfo(Carrier, Carrier);
	Asc->InitStats(UAbilitySystemTestAttributeSet::StaticClass(), nullptr);
	return Asc;
}

FGameplayModifierInfo Flat(
	const FGameplayAttribute& On, EGameplayModOp::Type Op, float Magnitude, int32 Channel)
{
	FGameplayModifierInfo Made;
	Made.Attribute = On;
	Made.ModifierOp = Op;
	Made.ModifierMagnitude = FGameplayEffectModifierMagnitude(FScalableFloat(Magnitude));
	Made.EvaluationChannelSettings.SetEvaluationChannel(
		static_cast<EGameplayModEvaluationChannel>(Channel));
	return Made;
}

UGameplayEffect* Instant(const TArray<FGameplayModifierInfo>& Modifiers);

UGameplayEffect* Infinite(const TArray<FGameplayModifierInfo>& Modifiers)
{
	UGameplayEffect* Effect =
		NewObject<UGameplayEffect>(GetTransientPackage(), NAME_None);
	Effect->DurationPolicy = EGameplayEffectDurationType::Infinite;
	Effect->Modifiers = Modifiers;
	// Rooted for the run. FAggregatorMod keeps raw pointers into the
	// FGameplayModifierInfo this definition owns - SourceTagReqs and
	// TargetTagReqs are `const FGameplayTagRequirements*` - so a definition
	// that is collected leaves an aggregator reading freed memory, and a
	// requirement that can never be satisfied is what that looks like from
	// outside.
	Effect->AddToRoot();
	return Effect;
}

UGameplayEffect* Instant(const TArray<FGameplayModifierInfo>& Modifiers)
{
	UGameplayEffect* Effect =
		NewObject<UGameplayEffect>(GetTransientPackage(), NAME_None);
	Effect->DurationPolicy = EGameplayEffectDurationType::Instant;
	Effect->Modifiers = Modifiers;
	Effect->AddToRoot();
	return Effect;
}

bool Apply(UAbilitySystemComponent* Asc, UGameplayEffect* Effect)
{
	FGameplayEffectContextHandle Context = Asc->MakeEffectContext();
	FGameplayEffectSpec Spec(Effect, Context, 1.0f);
	return Asc->ApplyGameplayEffectSpecToSelf(Spec).WasSuccessfullyApplied();
}

/** What one composition scenario is: apply once, then read the attribute and
 *  the base it did not touch. */
TSharedPtr<FJsonObject> Reading(
	UAbilitySystemComponent* Asc, const TCHAR* Which, const FString& Prefix, bool Landed)
{
	const FGameplayAttribute On = Attribute(Which);
	TSharedPtr<FJsonObject> Said = MakeShared<FJsonObject>();
	Said->SetBoolField(TEXT("applied"), Landed);
	Said->SetNumberField(Prefix + TEXT("_current"), Asc->GetNumericAttribute(On));
	Said->SetNumberField(Prefix + TEXT("_base"), Asc->GetNumericAttributeBase(On));
	return Said;
}

TSharedPtr<FJsonObject> Composed(UWorld* World, const TArray<FGameplayModifierInfo>& Mods)
{
	UAbilitySystemComponent* Asc = Fresh(World);
	Asc->SetNumericAttributeBase(Attribute(AttackName), 10.0f);
	const bool Landed = Apply(Asc, Infinite(Mods));
	return Reading(Asc, AttackName, TEXT("attack"), Landed);
}

/** Whether every channel a scenario names is one this project actually has.
 *  A channel that is not enabled is refused and collapses into Channel0, and a
 *  scenario about two channels then measures one. */
bool ChannelsUsable(const TArray<int32>& Channels)
{
	for (int32 Channel : Channels)
	{
		if (!UAbilitySystemGlobals::Get().IsGameplayModEvaluationChannelValid(
				static_cast<EGameplayModEvaluationChannel>(Channel)))
		{
			return false;
		}
	}
	return true;
}

/** Advance the world by one step.
 *
 *  The timer manager is ticked by hand. `UWorld::Tick` on a world built this
 *  way advances `TimeSeconds` and does not run timers - measured with a timer
 *  of this harness's own, set for one second and never fired over two. A
 *  periodic gameplay effect is driven by exactly that timer manager, so
 *  without this line the one scenario with a clock in it measures nothing. */
void Advance(UWorld* World, float Step)
{
	World->Tick(LEVELTICK_All, Step);
	// The frame counter, which is not decoration: FTimerManager ticks at most
	// once per frame, so a loop that ticks a world many times without moving it
	// runs the world's clock and never runs a timer. Measured with a timer of
	// this harness's own, set for one second and never fired over two - and it
	// is what Unreal's own GameplayEffectTests does between sub-ticks, with a
	// comment calling it terrible and doing it anyway.
	++GFrameCounter;
}

FGameplayTag TagNamed(const TCHAR* Named)
{
	return UGameplayTagsManager::Get().RequestGameplayTag(FName(Named), false);
}

FGameplayTagContainer Container(const TCHAR* Named)
{
	FGameplayTagContainer Made;
	Made.AddTag(TagNamed(Named));
	return Made;
}

/** A modifier that only counts when the target, or the source, carries a tag. */
FGameplayModifierInfo Qualified(
	const FGameplayAttribute& On, float Magnitude, const TCHAR* TargetNeeds,
	const TCHAR* SourceNeeds)
{
	FGameplayModifierInfo Made = Flat(On, EGameplayModOp::AddBase, Magnitude, 0);
	// Both the fields and the query. RequirementsMet reads one of them
	// depending on how the requirement was authored, and which one is not worth
	// guessing at when setting both costs nothing.
	if (TargetNeeds != nullptr)
	{
		Made.TargetTags.RequireTags = Container(TargetNeeds);
		Made.TargetTags.TagQuery =
			FGameplayTagQuery::MakeQuery_MatchAllTags(Container(TargetNeeds));
	}
	if (SourceNeeds != nullptr)
	{
		Made.SourceTags.RequireTags = Container(SourceNeeds);
		Made.SourceTags.TagQuery =
			FGameplayTagQuery::MakeQuery_MatchAllTags(Container(SourceNeeds));
	}
	return Made;
}

/** A magnitude that reads another attribute rather than a number. */
FGameplayModifierInfo Captured(
	const FGameplayAttribute& On,
	const FGameplayAttribute& From,
	float Coefficient,
	float PreMultiply,
	float PostMultiply,
	EAttributeBasedFloatCalculationType How,
	int32 UpTo,
	int32 Channel)
{
	FAttributeBasedFloat Reading;
	Reading.Coefficient = FScalableFloat(Coefficient);
	Reading.PreMultiplyAdditiveValue = FScalableFloat(PreMultiply);
	Reading.PostMultiplyAdditiveValue = FScalableFloat(PostMultiply);
	Reading.BackingAttribute = FGameplayEffectAttributeCaptureDefinition(
		From, EGameplayEffectAttributeCaptureSource::Target, false);
	Reading.AttributeCalculationType = How;
	Reading.FinalChannel = static_cast<EGameplayModEvaluationChannel>(UpTo);

	FGameplayModifierInfo Made;
	Made.Attribute = On;
	Made.ModifierOp = EGameplayModOp::AddBase;
	Made.ModifierMagnitude = FGameplayEffectModifierMagnitude(Reading);
	Made.EvaluationChannelSettings.SetEvaluationChannel(
		static_cast<EGameplayModEvaluationChannel>(Channel));
	return Made;
}
}  // namespace ParityRun

bool UParityScenarios::RunAll(UObject* WorldContext, const FString& OutPath)
{
	using namespace ParityRun;

	// A world of its own, begun. The editor world has never begun play, so its
	// timer manager does not drive a periodic effect and the one scenario with
	// a clock in it measured nothing - its control, which should have executed
	// most often, executed not at all. That is the shape of a harness lying, so
	// the harness gets a world that actually runs.
	UWorld* World = UWorld::CreateWorld(EWorldType::Game, false, TEXT("ParityWorld"));
	if (World == nullptr)
	{
		UE_LOG(LogParity, Error, TEXT("PARITY_NO_WORLD"));
		return false;
	}
	FWorldContext& Running = GEngine->CreateNewWorldContext(EWorldType::Game);
	Running.SetCurrentWorld(World);
	World->InitializeActorsForPlay(FURL());
	World->BeginPlay();
	ON_SCOPE_EXIT
	{
		GEngine->DestroyWorldContext(World);
		World->DestroyWorld(false);
	};
	if (!ChannelsUsable({0, 1, 2, 3}))
	{
		UE_LOG(LogParity, Error, TEXT("PARITY_NO_CHANNELS"));
		return false;
	}
	// A tag this project has not declared comes back invalid, and a RequireTags
	// container holding an invalid tag is never satisfied - so the qualification
	// scenario would answer "neither modifier counted" in all four variants and
	// look like a measurement of the rule rather than of a typo.
	for (const TCHAR* Needed : {TEXT("Status.Burning"), TEXT("Status.Empowered"),
								TEXT("Status.Inhibited")})
	{
		if (!TagNamed(Needed).IsValid())
		{
			UE_LOG(LogParity, Error, TEXT("PARITY_NO_TAG %s"), Needed);
			return false;
		}
	}

	const FGameplayAttribute Attack = Attribute(AttackName);
	const FGameplayAttribute Health = Attribute(HealthName);
	TSharedPtr<FJsonObject> Out = MakeShared<FJsonObject>();

	Out->SetObjectField(TEXT("legacy_multiply_one_and_a_half_twice"), Composed(World, {
		Flat(Attack, EGameplayModOp::MultiplyAdditive, 1.5f, 0),
		Flat(Attack, EGameplayModOp::MultiplyAdditive, 1.5f, 0)}));

	Out->SetObjectField(TEXT("multiply_compound_one_and_a_half_twice"), Composed(World, {
		Flat(Attack, EGameplayModOp::MultiplyCompound, 1.5f, 0),
		Flat(Attack, EGameplayModOp::MultiplyCompound, 1.5f, 0)}));

	Out->SetObjectField(TEXT("legacy_divide"), Composed(World, {
		Flat(Attack, EGameplayModOp::DivideAdditive, 2.0f, 0)}));

	Out->SetObjectField(TEXT("double_override_same_channel"), Composed(World, {
		Flat(Attack, EGameplayModOp::Override, 40.0f, 0),
		Flat(Attack, EGameplayModOp::Override, 70.0f, 0)}));

	Out->SetObjectField(TEXT("override_across_channels"), Composed(World, {
		Flat(Attack, EGameplayModOp::Override, 40.0f, 0),
		Flat(Attack, EGameplayModOp::Override, 70.0f, 1)}));

	// The order two overrides were given in, measured rather than reasoned: the
	// same scenario with the pair swapped. If the answer moves, order decides
	// it and the earlier one is the one that stands.
	TSharedPtr<FJsonObject> SwappedSame = Composed(World, {
		Flat(Attack, EGameplayModOp::Override, 70.0f, 0),
		Flat(Attack, EGameplayModOp::Override, 40.0f, 0)});
	TSharedPtr<FJsonObject> SwappedChannels = Composed(World, {
		Flat(Attack, EGameplayModOp::Override, 70.0f, 0),
		Flat(Attack, EGameplayModOp::Override, 40.0f, 1)});
	Out->SetObjectField(TEXT("_order_double_override_swapped"), SwappedSame);
	Out->SetObjectField(TEXT("_order_across_channels_swapped"), SwappedChannels);

	// --- the stack, with the factor off and then on -------------------------
	{
		TArray<TSharedPtr<FJsonValue>> Variants;
		for (bool Factored : {false, true})
		{
			UAbilitySystemComponent* Asc = Fresh(World);
			Asc->SetNumericAttributeBase(Attack, 10.0f);
			UGameplayEffect* Effect = Infinite({
				Flat(Attack, EGameplayModOp::AddBase, 5.0f, 0)});
			Effect->StackingType = EGameplayEffectStackingType::AggregateByTarget;
			Effect->StackLimitCount = 3;
			Effect->bDenyOverflowApplication = false;
			Effect->bFactorInStackCount = Factored;

			bool Landed = false;
			for (int32 Applied = 0; Applied < 3; ++Applied)
			{
				Landed = Apply(Asc, Effect);
			}
			Variants.Add(MakeShared<FJsonValueObject>(
				Reading(Asc, AttackName, TEXT("attack"), Landed)));
		}
		TSharedPtr<FJsonObject> Said = MakeShared<FJsonObject>();
		Said->SetArrayField(TEXT("variants"), Variants);
		Out->SetObjectField(TEXT("stack_count_factor_off_and_on"), Said);
	}

	// --- which side a qualification is read from ----------------------------
	{
		TArray<TSharedPtr<FJsonValue>> Variants;
		const bool Wears[4][2] = {{false, false}, {true, false}, {false, true}, {true, true}};
		for (const bool* Pair : Wears)
		{
			UAbilitySystemComponent* Target = Fresh(World);
			UAbilitySystemComponent* Source = Fresh(World);
			Target->SetNumericAttributeBase(Attack, 10.0f);
			if (Pair[0])
			{
				Target->AddLooseGameplayTag(TagNamed(TEXT("Status.Burning")));
			}
			if (Pair[1])
			{
				Source->AddLooseGameplayTag(TagNamed(TEXT("Status.Empowered")));
			}

			UGameplayEffect* Effect = Infinite({
				Qualified(Attack, 5.0f, TEXT("Status.Burning"), nullptr),
				Qualified(Attack, 7.0f, nullptr, TEXT("Status.Empowered"))});
			FGameplayEffectContextHandle Context = Source->MakeEffectContext();
			FGameplayEffectSpec Spec(Effect, Context, 1.0f);
			const bool Landed =
				Source->ApplyGameplayEffectSpecToTarget(Spec, Target).WasSuccessfullyApplied();
			TSharedPtr<FJsonObject> Said = Reading(Target, AttackName, TEXT("attack"), Landed);
			FGameplayTagContainer Owned;
			Target->GetOwnedGameplayTags(Owned);
			Said->SetStringField(TEXT("_target_owned"), Owned.ToStringSimple());
			Source->GetOwnedGameplayTags(Owned);
			Said->SetStringField(TEXT("_source_owned"), Owned.ToStringSimple());
			// What the spec captured is what a requirement is checked against,
			// and a requirement that always filters with RequireTags and never
			// filters with IgnoreTags is what an empty container looks like.
			for (const FActiveGameplayEffect& Active :
				 &Target->GetActiveGameplayEffects())
			{
				Said->SetStringField(TEXT("_captured_target"),
					Active.Spec.CapturedTargetTags.GetActorTags().ToStringSimple());
				Said->SetStringField(TEXT("_captured_source"),
					Active.Spec.CapturedSourceTags.GetActorTags().ToStringSimple());
				break;
			}
			Variants.Add(MakeShared<FJsonValueObject>(Said));
		}
		TSharedPtr<FJsonObject> Said = MakeShared<FJsonObject>();
		Said->SetArrayField(TEXT("variants"), Variants);
		Out->SetObjectField(TEXT("modifier_source_and_target_tag_qualification"), Said);

		// The same four, as an execution rather than a persistent modifier.
		//
		// Unreal recomputes a persistent aggregator without source or target
		// tags on purpose - GameplayEffect.cpp says so where it does it: "this
		// is not an execution, so there are no 'source' and 'target' tags to
		// fill out". So a modifier's own requirement is never met under an
		// infinite effect, whatever either side is carrying, and an instant one
		// is where the question the golden asks can actually be answered.
		{
			TArray<TSharedPtr<FJsonValue>> Executed;
			const bool Wearing[4][2] = {{false, false}, {true, false},
										{false, true}, {true, true}};
			for (const bool* Pair : Wearing)
			{
				UAbilitySystemComponent* Target = Fresh(World);
				UAbilitySystemComponent* Source = Fresh(World);
				Target->SetNumericAttributeBase(Attack, 10.0f);
				if (Pair[0])
				{
					Target->AddLooseGameplayTag(TagNamed(TEXT("Status.Burning")));
				}
				if (Pair[1])
				{
					Source->AddLooseGameplayTag(TagNamed(TEXT("Status.Empowered")));
				}
				UGameplayEffect* Once = Instant({
					Qualified(Attack, 5.0f, TEXT("Status.Burning"), nullptr),
					Qualified(Attack, 7.0f, nullptr, TEXT("Status.Empowered"))});
				FGameplayEffectContextHandle Context = Source->MakeEffectContext();
				FGameplayEffectSpec Spec(Once, Context, 1.0f);
				const bool Landed = Source->ApplyGameplayEffectSpecToTarget(Spec, Target)
										.WasSuccessfullyApplied();
				Executed.Add(MakeShared<FJsonValueObject>(
					Reading(Target, AttackName, TEXT("attack"), Landed)));
			}
			TSharedPtr<FJsonObject> AsExecution = MakeShared<FJsonObject>();
			AsExecution->SetArrayField(TEXT("variants"), Executed);
			Out->SetObjectField(TEXT("_tag_qualification_as_an_execution"), AsExecution);
		}

		// Controls, because four identical answers are also what a harness that
		// applied nothing would say. One plain modifier across the same
		// source-to-target path, and one qualified modifier whose requirement is
		// met, asked separately.
		{
			UAbilitySystemComponent* Target = Fresh(World);
			UAbilitySystemComponent* Source = Fresh(World);
			Target->SetNumericAttributeBase(Attack, 10.0f);
			UGameplayEffect* Plain = Infinite({Flat(Attack, EGameplayModOp::AddBase, 5.0f, 0)});
			FGameplayEffectContextHandle Context = Source->MakeEffectContext();
			FGameplayEffectSpec Spec(Plain, Context, 1.0f);
			const bool Landed =
				Source->ApplyGameplayEffectSpecToTarget(Spec, Target).WasSuccessfullyApplied();
			Out->SetObjectField(TEXT("_tag_control_no_requirement"),
				Reading(Target, AttackName, TEXT("attack"), Landed));
		}
		{
			UAbilitySystemComponent* Target = Fresh(World);
			Target->SetNumericAttributeBase(Attack, 10.0f);
			Target->AddLooseGameplayTag(TagNamed(TEXT("Status.Burning")));
			UGameplayEffect* One = Infinite({
				Qualified(Attack, 5.0f, TEXT("Status.Burning"), nullptr)});
			const bool Landed = Apply(Target, One);
			Out->SetObjectField(TEXT("_tag_control_target_requirement_met_on_self"),
				Reading(Target, AttackName, TEXT("attack"), Landed));
		}
		{
			// Whether a requirement is consulted at all, asked the other way
			// round: a modifier that must NOT see a tag the target does not
			// have. If this applies and the must-have one does not, the
			// requirement is being read and only RequireTags is failing.
			UAbilitySystemComponent* Target = Fresh(World);
			Target->SetNumericAttributeBase(Attack, 10.0f);
			FGameplayModifierInfo Avoiding =
				Flat(Attack, EGameplayModOp::AddBase, 5.0f, 0);
			Avoiding.TargetTags.IgnoreTags = Container(TEXT("Status.Burning"));
			const bool Landed = Apply(Target, Infinite({Avoiding}));
			Out->SetObjectField(TEXT("_tag_control_must_not_have_and_does_not"),
				Reading(Target, AttackName, TEXT("attack"), Landed));
		}
		{
			// The same, with the tag present, which must filter it out.
			UAbilitySystemComponent* Target = Fresh(World);
			Target->SetNumericAttributeBase(Attack, 10.0f);
			Target->AddLooseGameplayTag(TagNamed(TEXT("Status.Burning")));
			FGameplayModifierInfo Avoiding =
				Flat(Attack, EGameplayModOp::AddBase, 5.0f, 0);
			Avoiding.TargetTags.IgnoreTags = Container(TEXT("Status.Burning"));
			const bool Landed = Apply(Target, Infinite({Avoiding}));
			Out->SetObjectField(TEXT("_tag_control_must_not_have_and_does"),
				Reading(Target, AttackName, TEXT("attack"), Landed));
		}
		{
			// The tag arriving after the effect did. A requirement checked at
			// application is a snapshot; one checked at evaluation is live, and
			// which of the two it is changes what this scenario even asks.
			UAbilitySystemComponent* Target = Fresh(World);
			Target->SetNumericAttributeBase(Attack, 10.0f);
			UGameplayEffect* One = Infinite({
				Qualified(Attack, 5.0f, TEXT("Status.Burning"), nullptr)});
			const bool Landed = Apply(Target, One);
			Target->AddLooseGameplayTag(TagNamed(TEXT("Status.Burning")));
			Out->SetObjectField(TEXT("_tag_control_requirement_met_after_applying"),
				Reading(Target, AttackName, TEXT("attack"), Landed));
		}
	}

	// --- a captured magnitude, composing its coefficients -------------------
	{
		UAbilitySystemComponent* Asc = Fresh(World);
		Asc->SetNumericAttributeBase(Attack, 10.0f);
		Asc->SetNumericAttributeBase(Health, 100.0f);
		const bool Landed = Apply(Asc, Infinite({
			Captured(Health, Attack, 2.0f, 1.0f, 3.0f,
				EAttributeBasedFloatCalculationType::AttributeBonusMagnitude, 0, 0)}));
		Out->SetObjectField(TEXT("bonus_magnitude"),
			Reading(Asc, HealthName, TEXT("health"), Landed));
	}

	// --- a captured magnitude read only as far as a channel -----------------
	{
		UAbilitySystemComponent* Asc = Fresh(World);
		Asc->SetNumericAttributeBase(Attack, 10.0f);
		Asc->SetNumericAttributeBase(Health, 100.0f);
		const bool Landed = Apply(Asc, Infinite({
			Flat(Attack, EGameplayModOp::AddBase, 5.0f, 0),
			Flat(Attack, EGameplayModOp::AddBase, 100.0f, 2),
			Captured(Health, Attack, -1.0f, 0.0f, 0.0f,
				EAttributeBasedFloatCalculationType::AttributeMagnitudeEvaluatedUpToChannel,
				1, 3)}));
		TSharedPtr<FJsonObject> Said =
			Reading(Asc, HealthName, TEXT("health"), Landed);
		Said->SetNumberField(TEXT("attack_current"), Asc->GetNumericAttribute(Attack));
		Said->SetNumberField(TEXT("attack_base"), Asc->GetNumericAttributeBase(Attack));
		Out->SetObjectField(TEXT("magnitude_up_to_channel"), Said);
	}

	// --- a sub-period inhibition, on a clock this drives --------------------
	{
		UAbilitySystemComponent* Asc = Fresh(World);
		Asc->SetNumericAttributeBase(Health, 100.0f);
		UGameplayEffect* Effect = Infinite({
			Flat(Health, EGameplayModOp::AddBase, -5.0f, 0)});
		Effect->Period = FScalableFloat(1.0f);
		Effect->bExecutePeriodicEffectOnApplication = true;
		Effect->PeriodicInhibitionPolicy =
			EGameplayEffectPeriodInhibitionRemovedPolicy::ExecuteAndResetPeriod;
		// Inhibited by a tag the target can be made to carry and then not,
		// which is the only way a test can turn inhibition on and off.
		Effect->OngoingTagRequirements.IgnoreTags = Container(TEXT("Status.Inhibited"));

		const bool Landed = Apply(Asc, Effect);
		// The world's timers rather than the world: an editor world has never
		// begun play and ticking it whole asserts, while the periodic execution
		// this scenario is about is driven by the timer manager.
		// The golden's timeline, each event once. An earlier version toggled on
		// a pair of conditions and re-inhibited on the very next step, so the
		// effect executed on every other tick and answered a number that was
		// about the loop.
		const float Step = 0.05f;
		float Ran = 0.0f;
		bool Started = false;
		bool Stopped = false;
		FString Trace;
		float Was = Asc->GetNumericAttribute(Health);
		while (Ran < 2.5f)
		{
			Advance(World, Step);
			Ran += Step;
			const float Now = Asc->GetNumericAttribute(Health);
			if (!FMath::IsNearlyEqual(Now, Was))
			{
				Trace += FString::Printf(TEXT("%.2f:%.0f "), Ran, Now);
				Was = Now;
			}
			if (!Started && Ran >= 0.4f)
			{
				Asc->AddLooseGameplayTag(TagNamed(TEXT("Status.Inhibited")));
				Started = true;
			}
			if (Started && !Stopped && Ran >= 0.7f)
			{
				Asc->RemoveLooseGameplayTag(TagNamed(TEXT("Status.Inhibited")));
				Stopped = true;
			}
		}
		TSharedPtr<FJsonObject> Timed =
			Reading(Asc, HealthName, TEXT("health"), Landed);
		Timed->SetStringField(TEXT("_trace"), Trace);
		Out->SetObjectField(
			TEXT("short_inhibition_with_execute_and_reset_period"), Timed);

		// The same clock with nothing inhibited. Written down because the two
		// can come out the same, and a reader is entitled to know that this
		// scenario does not distinguish them rather than to assume it does.
		UAbilitySystemComponent* Control = Fresh(World);
		Control->SetNumericAttributeBase(Health, 100.0f);
		UGameplayEffect* Plain = Infinite({
			Flat(Health, EGameplayModOp::AddBase, -5.0f, 0)});
		Plain->Period = FScalableFloat(1.0f);
		Plain->bExecutePeriodicEffectOnApplication = true;
		const bool ControlLanded = Apply(Control, Plain);
		for (float Went = 0.0f; Went < 2.5f; Went += Step)
		{
			Advance(World, Step);
		}
		TSharedPtr<FJsonObject> ControlSaid =
			Reading(Control, HealthName, TEXT("health"), ControlLanded);
		// Whether the clock moved at all. Zero executions and a stopped clock
		// are the same number and not the same finding.
		ControlSaid->SetNumberField(TEXT("_world_seconds"), World->GetTimeSeconds());
		// What the definition says, and what a spec built from it says. If the
		// two disagree the period never reached the application, which is a
		// different finding from a clock that did not run.
		ControlSaid->SetNumberField(TEXT("_def_period"), Plain->Period.GetValueAtLevel(1.0f));
		FGameplayEffectContextHandle Asked = Control->MakeEffectContext();
		FGameplayEffectSpec Reading(Plain, Asked, 1.0f);
		ControlSaid->SetNumberField(TEXT("_spec_period"), Reading.GetPeriod());
		ControlSaid->SetNumberField(TEXT("_spec_duration"), Reading.GetDuration());
		ControlSaid->SetBoolField(
			TEXT("_authoritative"), Control->IsOwnerActorAuthoritative());
		ControlSaid->SetNumberField(
			TEXT("_active_count"), Control->GetActiveEffects(FGameplayEffectQuery()).Num());

		// A timer of this harness's own, on the same world and the same clock.
		// If it does not fire, the finding is "the timer manager is not being
		// ticked" and not anything about gameplay effects.
		bool Fired = false;
		FTimerHandle Ticket;
		World->GetTimerManager().SetTimer(
			Ticket, FTimerDelegate::CreateLambda([&Fired]() { Fired = true; }), 1.0f, false);
		for (float Went = 0.0f; Went < 2.0f; Went += Step)
		{
			Advance(World, Step);
		}
		ControlSaid->SetBoolField(TEXT("_own_timer_fired"), Fired);
		Out->SetObjectField(TEXT("_inhibition_control_never_inhibited"), ControlSaid);
	}

	FString Text;
	TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Text);
	FJsonSerializer::Serialize(Out.ToSharedRef(), Writer);
	if (!FFileHelper::SaveStringToFile(Text, *OutPath))
	{
		UE_LOG(LogParity, Error, TEXT("PARITY_UNWRITABLE %s"), *OutPath);
		return false;
	}
	UE_LOG(LogParity, Display, TEXT("PARITY_WROTE %s"), *OutPath);
	return true;
}
