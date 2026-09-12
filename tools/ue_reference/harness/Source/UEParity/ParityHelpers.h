// The one thing the reference harness cannot reach from Python.
//
// UAbilitySystemComponent::InitAbilityActorInfo is not a UFUNCTION, and every
// route into applying a GameplayEffect dereferences AbilityActorInfo. The
// scenario assembly itself is all reflected and lives in Python; this exposes
// the initialiser and two readings, and nothing else.

#pragma once

#include "CoreMinimal.h"
#include "AttributeSet.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "ParityHelpers.generated.h"

class UAbilitySystemComponent;

UCLASS()
class UParityHelpers : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** Give the component the actor info every apply path assumes it has. */
	UFUNCTION(BlueprintCallable, Category = "Parity")
	static void InitActorInfo(UAbilitySystemComponent* Asc, AActor* Owner, AActor* Avatar);

	/** The durable base value, which is not what GetGameplayAttributeValue answers. */
	UFUNCTION(BlueprintCallable, Category = "Parity")
	static float BaseValue(UAbilitySystemComponent* Asc, FGameplayAttribute Attribute);

	/** The composed current value, for symmetry with the base reading. */
	UFUNCTION(BlueprintCallable, Category = "Parity")
	static float CurrentValue(UAbilitySystemComponent* Asc, FGameplayAttribute Attribute);

	/** Set the base without going through an effect, to seed a scenario. */
	UFUNCTION(BlueprintCallable, Category = "Parity")
	static void SetBaseValue(UAbilitySystemComponent* Asc, FGameplayAttribute Attribute, float Value);
};
