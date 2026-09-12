#include "ParityHelpers.h"

#include "AbilitySystemComponent.h"
#include "AbilitySystemGlobals.h"

void UParityHelpers::InitActorInfo(UAbilitySystemComponent* Asc, AActor* Owner, AActor* Avatar)
{
	if (Asc == nullptr)
	{
		return;
	}

	// Registered first. A component made with NewObject and never registered
	// never has InitializeComponent run on it, so AbilityActorInfo was never
	// allocated - and InitAbilityActorInfo opens with check(IsValid()), which
	// takes the process down rather than answering. RegisterComponent is not a
	// UFUNCTION either, which is the other half of why this file exists.
	if (!Asc->IsRegistered())
	{
		Asc->RegisterComponent();
	}
	Asc->InitAbilityActorInfo(Owner, Avatar);
}

float UParityHelpers::BaseValue(UAbilitySystemComponent* Asc, FGameplayAttribute Attribute)
{
	return Asc != nullptr ? Asc->GetNumericAttributeBase(Attribute) : 0.0f;
}

float UParityHelpers::CurrentValue(UAbilitySystemComponent* Asc, FGameplayAttribute Attribute)
{
	return Asc != nullptr ? Asc->GetNumericAttribute(Attribute) : 0.0f;
}

void UParityHelpers::SetBaseValue(UAbilitySystemComponent* Asc, FGameplayAttribute Attribute, float Value)
{
	if (Asc != nullptr)
	{
		Asc->SetNumericAttributeBase(Attribute, Value);
	}
}

bool UParityHelpers::WasApplied(FActiveGameplayEffectHandle Handle)
{
	return Handle.WasSuccessfullyApplied();
}

bool UParityHelpers::ChannelIsUsable(int32 Channel)
{
	return UAbilitySystemGlobals::Get().IsGameplayModEvaluationChannelValid(
		static_cast<EGameplayModEvaluationChannel>(Channel));
}
