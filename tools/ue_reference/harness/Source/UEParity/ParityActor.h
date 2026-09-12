// An actor that says it has an ability system, because GAS asks.
//
// A plain AActor carrying an ASC is not enough: the source tags a modifier
// qualifies on are captured through
// UAbilitySystemGlobals::GetAbilitySystemComponentFromActor, which finds one
// only through IAbilitySystemInterface. Without it the instigator's component
// is null, nothing is captured, and every tag-qualified modifier is filtered
// out - which reads as "the rule says no" rather than as "nobody was asked".

#pragma once

#include "AbilitySystemInterface.h"
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ParityActor.generated.h"

class UAbilitySystemComponent;

UCLASS()
class AParityActor : public AActor, public IAbilitySystemInterface
{
	GENERATED_BODY()

public:
	AParityActor();

	virtual UAbilitySystemComponent* GetAbilitySystemComponent() const override;

private:
	UPROPERTY()
	TObjectPtr<UAbilitySystemComponent> Abilities;
};
