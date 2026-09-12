// The ten scenarios of test/parity/goldens/, run against a real ability system.
//
// In C++ rather than Python because four of them need something reflection does
// not reach: an attribute-based magnitude, a modifier's own tag requirements, a
// stack, and a world that ticks. Everything here is built from the `inputs`
// block of its golden and nothing else - not from that repository's engine, and
// not from a reading of Unreal's documentation.

#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "ParityScenarios.generated.h"

UCLASS()
class UParityScenarios : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** Run all ten and write what happened, as JSON, to `OutPath`. */
	UFUNCTION(BlueprintCallable, Category = "Parity")
	static bool RunAll(UObject* WorldContext, const FString& OutPath);
};
