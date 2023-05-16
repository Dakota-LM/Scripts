1. Create a new ImmyBot function
2. Name it Send-LocalMDMRequest
3. Copy the contents of the Send-LocalMDMRequest.ps1 file into it
4. Save it
5. Copy the contents of Unregister-LocalMDM.ps1 into another new function and save it
6. Create a new task named "Enforce MDM Command" or something
7. Add 4 parameters: Unregister (a boolean with default $false), OMAURI (Text requiring user input), SetCmd ("select" with options Add, Exec, Delete, and Replace), and DataValue (Text requiring user input)
8. Copy the combined script from this repo into a new combined script in the task
9. Save the task and it is now usable
10. Look up the CSP you need in MS docs, copy the OMAURI into the corresponding parameter
11. Set the SetCmd and DataValue to what is required for it to work according to the documentation


NOTE: It is advised to always run a test on a non-remote computer before using for production purposes!
