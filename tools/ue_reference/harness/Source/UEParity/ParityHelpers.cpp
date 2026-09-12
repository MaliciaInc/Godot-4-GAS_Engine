#include "ParityHelpers.h"

#include "AbilitySystemComponent.h"

void UParityHelpers::InitActorInfo(UAbilitySystemComponent* Asc, AActor* Owner, AActor* Avatar)
{
	if (Asc != nullptr)
	{
		Asc->InitAbilityActorInfo(Owner, Avatar);
	}
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
