// The reference run, in a game target because the editor target cannot be
// built on this machine: UnrealBuildTool refuses without a .NET Framework SDK,
// which SwarmInterface needs and which only UnrealEd pulls in.
//
// Every scenario is built from its golden's `inputs` block and applied to a
// real UAbilitySystemComponent. Nothing here reads this repository's engine or
// its documentation; what comes out is what Unreal did.

#pragma once

#include "CoreMinimal.h"
#include "Engine/GameInstance.h"
#include "ParityGameInstance.generated.h"

UCLASS()
class UParityGameInstance : public UGameInstance
{
	GENERATED_BODY()

public:
	virtual void Init() override;
};
