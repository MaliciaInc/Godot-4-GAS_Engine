#include "ParityActor.h"

#include "AbilitySystemComponent.h"

AParityActor::AParityActor()
{
	Abilities = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("Abilities"));
	PrimaryActorTick.bCanEverTick = true;
}

UAbilitySystemComponent* AParityActor::GetAbilitySystemComponent() const
{
	return Abilities;
}
