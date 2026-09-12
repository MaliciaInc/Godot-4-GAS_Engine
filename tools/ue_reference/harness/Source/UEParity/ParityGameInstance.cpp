#include "ParityGameInstance.h"

#include "AbilitySystemComponent.h"
#include "AbilitySystemTestAttributeSet.h"
#include "GameFramework/Actor.h"
#include "GameplayEffect.h"
#include "GameplayEffectTypes.h"
#include "HAL/PlatformMisc.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "Dom/JsonObject.h"

namespace
{
/** "attack" and "health" in the goldens, on the set the plugin already ships. */
const TCHAR* AttackName = TEXT("Strength");
const TCHAR* HealthName = TEXT("PhysicalDamage");

FGameplayAttribute AttributeNamed(const TCHAR* Named)
{
	FProperty* Found = FindFProperty<FProperty>(
		UAbilitySystemTestAttributeSet::StaticClass(), Named);
	return FGameplayAttribute(Found);
}

/** A component with nothing on it, because five scenarios sharing one
 *  character compose on top of each other and the fifth reads as a
 *  measurement.
 *
 *  Built without a world on purpose. This runs before a map is loaded, because
 *  an uncooked project in a game binary cannot load one, and composition is
 *  arithmetic: it needs an aggregator and an attribute set, not a level. */
UAbilitySystemComponent* FreshComponent()
{
	AActor* Carrier = NewObject<AActor>(GetTransientPackage());
	UAbilitySystemComponent* Asc = NewObject<UAbilitySystemComponent>(Carrier);
	Asc->InitAbilityActorInfo(Carrier, Carrier);
	Asc->InitStats(UAbilitySystemTestAttributeSet::StaticClass(), nullptr);
	return Asc;
}

FGameplayModifierInfo Modifier(
	const FGameplayAttribute& Attribute,
	EGameplayModOp::Type Operation,
	float Magnitude,
	int32 Channel)
{
	FGameplayModifierInfo Made;
	Made.Attribute = Attribute;
	Made.ModifierOp = Operation;
	Made.ModifierMagnitude = FGameplayEffectModifierMagnitude(FScalableFloat(Magnitude));
	Made.EvaluationChannelSettings.SetEvaluationChannel(
		static_cast<EGameplayModEvaluationChannel>(Channel));
	return Made;
}

/** One infinite effect carrying those modifiers, applied once. */
bool Applied(UAbilitySystemComponent* Asc, const TArray<FGameplayModifierInfo>& Modifiers)
{
	UGameplayEffect* Effect = NewObject<UGameplayEffect>(
		GetTransientPackage(), FName(TEXT("GE_Parity")));
	Effect->DurationPolicy = EGameplayEffectDurationType::Infinite;
	Effect->Modifiers = Modifiers;

	FGameplayEffectContextHandle Context = Asc->MakeEffectContext();
	FGameplayEffectSpec Spec(Effect, Context, 1.0f);
	return Asc->ApplyGameplayEffectSpecToSelf(Spec).IsValid();
}

TSharedPtr<FJsonObject> Composed(const TArray<FGameplayModifierInfo>& Modifiers)
{
	UAbilitySystemComponent* Asc = FreshComponent();
	const FGameplayAttribute Attack = AttributeNamed(AttackName);
	Asc->SetNumericAttributeBase(Attack, 10.0f);

	const bool Landed = Applied(Asc, Modifiers);

	TSharedPtr<FJsonObject> Said = MakeShared<FJsonObject>();
	Said->SetBoolField(TEXT("applied"), Landed);
	Said->SetNumberField(TEXT("attack_current"), Asc->GetNumericAttribute(Attack));
	Said->SetNumberField(TEXT("attack_base"), Asc->GetNumericAttributeBase(Attack));
	return Said;
}
}  // namespace

void UParityGameInstance::Init()
{
	Super::Init();

	TSharedPtr<FJsonObject> Out = MakeShared<FJsonObject>();
	const FGameplayAttribute Attack = AttributeNamed(AttackName);

	{
		TArray<FGameplayModifierInfo> Mods;
		Mods.Add(Modifier(Attack, EGameplayModOp::MultiplyAdditive, 1.5f, 0));
		Mods.Add(Modifier(Attack, EGameplayModOp::MultiplyAdditive, 1.5f, 0));
		Out->SetObjectField(TEXT("legacy_multiply_one_and_a_half_twice"), Composed(Mods));
	}
	{
		TArray<FGameplayModifierInfo> Mods;
		Mods.Add(Modifier(Attack, EGameplayModOp::MultiplyCompound, 1.5f, 0));
		Mods.Add(Modifier(Attack, EGameplayModOp::MultiplyCompound, 1.5f, 0));
		Out->SetObjectField(TEXT("multiply_compound_one_and_a_half_twice"), Composed(Mods));
	}
	{
		TArray<FGameplayModifierInfo> Mods;
		Mods.Add(Modifier(Attack, EGameplayModOp::DivideAdditive, 2.0f, 0));
		Out->SetObjectField(TEXT("legacy_divide"), Composed(Mods));
	}
	{
		TArray<FGameplayModifierInfo> Mods;
		Mods.Add(Modifier(Attack, EGameplayModOp::Override, 40.0f, 0));
		Mods.Add(Modifier(Attack, EGameplayModOp::Override, 70.0f, 0));
		Out->SetObjectField(TEXT("double_override_same_channel"), Composed(Mods));
	}
	{
		TArray<FGameplayModifierInfo> Mods;
		Mods.Add(Modifier(Attack, EGameplayModOp::Override, 40.0f, 0));
		Mods.Add(Modifier(Attack, EGameplayModOp::Override, 70.0f, 1));
		Out->SetObjectField(TEXT("override_across_channels"), Composed(Mods));
	}

	FString Text;
	TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Text);
	FJsonSerializer::Serialize(Out.ToSharedRef(), Writer);
	const FString Where = FPaths::Combine(FPaths::ProjectDir(), TEXT("ue_reference_out.json"));
	FFileHelper::SaveStringToFile(Text, *Where);
	UE_LOG(LogTemp, Display, TEXT("PARITY_WROTE %s"), *Where);

	FPlatformMisc::RequestExit(false);
}
