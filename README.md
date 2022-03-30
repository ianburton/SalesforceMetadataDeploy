# SalesforceMetadataDeploy
A more complete deployment script for Salesforce

## Usage
Run script 'build.sh' with all paramaters, in the same level as your salesforce 'src' folder.

### Example:
./build.sh "$(bitbucket_account)" "$(bitbucket_pass)" "$(System.DefaultWorkingDirectory)" "$(bitbucket_pr_target)" "$(bitbucket_pr_source)" "$(IncludeDestructiveChanges)" "$(ValidateOnly)" "$(meta_to_exclude)" "$(meta_names_to_exclude)" $(username) "https://test.salesforce.com" "$(bitbucket_url)" "$(bitbucket_repo_slug)" "$(bitbucket_repo)" "$(bitbucket_reponame)" "$(bitbucket_account)" "$(bitbucket_pass)" "$(bitbucket_pr_number)" "$(auto_merge)" "$(PackageVersion)"


NOTES:
bitbucket_account = your bitbucket username

bitbucket_pass = your bitbucket password

System.DefaultWorkingDirectory = Azure Devops global, for current directory

bitbucket_pr_target = Pull request Target branch

bitbucket_pr_source = Pull request Source branch

IncludeDestructiveChanges = true if you want to create a destructiuve changes manifest with your package

ValidateOnly = true if you want to just run a validate

meta_to_exclude needs to be an array eg. ("objects" "flows") 

meta_names_to_exclude needs to be an array eg. ("Account" "Lead_Process_Flow__c") 

username = your salesforce username 

"https://test.salesforce.com" = salesforce instance URL (test for sandbox, login for prod)

bitbucket_url = your bitbucket instance URL ( https://USERNAME@bitbucket.org/REPOSLUG/REPONAME.git )

bitbucket_repo_slug = your bitbucket repository slug

bitbucket_repo = your bitbucket repo name

bitbucket_reponame = your git repo name

bitbucket_account = your bitbucket user account

bitbucket_pass = your bitbucket password

bitbucket_pr_number = your bitbucket pull request number 

auto_merge = true if you want the code to automatically merge the pull request, if the deployment succeeds (not enabled currently)

PackageVersion = salesforce package xml version (default is hardcoded to 48 if this is not set)
