# Primary sources checked for0.19

28 October2026. No third-party implementation copied; these constrain the original implementation.

- https://learn.microsoft.com/dotnet/framework/ui-automation/use-the-automationid-property — AutomationId needs container/scope and is not globally unique.
- https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-usefortesting — Name need not be unique, AutomationId need not exist/be stable across app releases, RuntimeId is opaque and can be reused. Current context matching is a bounded heuristic, not permanent identity.
- https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-treeoverview — UIA tree is dynamic and can be large; never treat a bounded snapshot as the whole application.
- https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.selectionitempattern.selectionitempatterninformation.isselected — selected-state observation, not acknowledgement of Select, is used for postcondition checks.

Source files/native tests, not website claims, establish implemented0.19behavior. Windows UIA was not executed here.
