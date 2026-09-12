using UnrealBuildTool;

public class UEParity : ModuleRules
{
	public UEParity(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] {
			"Core", "CoreUObject", "Engine", "GameplayAbilities", "GameplayTags", "GameplayTasks",
			// The editor target links modularly, so what the results are written
			// with has to be asked for by name. A monolithic game target had it
			// by accident and linked clean without it.
			"Json"
		});
	}
}
