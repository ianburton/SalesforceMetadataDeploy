set -x
echo 'Prepare variables'
git_username="$1"
git_pass="$2"
home_dir="$3"	## assign $(System.DefaultWorkingDirectory)

TargetBranch="$4"
SourceBranch="$5"
IncludeDestructiveChanges="$6"
ValidateOnly="$7"

MetaToExclude=("$8")
MetaNamesToExclude=("$9")

EnvironmentUserName="${10}"
instanceurl="${11}"

bitbucket_url="${12}"
bitbucket_workspace="${13}"
bitbucket_reposlug="${14}"
bitbucket_reponame="${15}"
bitbucket_account="${16}"
bitbucket_pass="${17}"
pr_number="${18}"

PackageVersion="${19}"

if [[ "$PackageVersion" == "" ]]; then
      PackageVersion="48.0"
fi 

echo 'Checkout code'
git clone https://${git_username}:"${git_pass}"@bitbucket.org/${bitbucket_reposlug}/${bitbucket_reponame}.git --branch master 
cd ${bitbucket_reponame}
echo 'list all the branches'
git branch
echo 'list master'
ls -ltra

mkdir -p deployPackage

echo "Shell Start to generate package.xml ..."

bash $home_dir/GetBranchDiff.sh $SourceBranch $TargetBranch "$home_dir/filenamediff.txt"

# now that we have a list of the files that have changed, lets build a package and zip file
bash $home_dir/BuildPackage.sh "$home_dir/filenamediff.txt" $IncludeDestructiveChanges "$MetaToExclude" "$MetaNamesToExclude" "$EnvironmentUserName" "$SourceBranch" "$TargetBranch" "$PackageVersion"

validateparam=""
if [[ "$ValidateOnly" == "true" ]]; then
           validateparam="--checkonly"
else
           validateparam=""
fi

echo "Starting Async Deploy" 
deployid=$(sfdx force:mdapi:deploy -d deployPackage/src -u "$EnvironmentUserName" $validateparam --testlevel RunLocalTests --json | jq -r '.result.id')

echo "Deployment ID:"$deployid
isdone=false;
while [ "$isdone" == false ]
do
sfdxpollresult=$(echo $(sfdx force:mdapi:deploy:report -u "$EnvironmentUserName" -i $deployid --json) )
isdone=$(echo $sfdxpollresult | jq '.result.done')
statusis=$(echo $sfdxpollresult | jq '.result.status')
echo "Deploy Status:"$statusis

 sleep 5

done

# deployment is complete, lets check if it succeeded
sfdxresult=$(echo $(sfdx force:mdapi:deploy:report -u "$EnvironmentUserName" -i $deployid --json) )
echo "Writing Result To file";

echo $sfdxresult > "$home_dir"/testresults.json

doneval=$(echo $sfdxresult | jq '.result.done')
statusval=$(echo $sfdxresult | jq '.result.status')
successval=$(echo $sfdxresult | jq '.result.success')

echo "doneval:"$doneval
echo "statusval:"$statusval
echo "successval:"$successval

if [[ ${successval^^} == "TRUE" ]]; then
      echo "Deployment Suceeded!"
    # then we can merge the PR
   
   exit 0
else
    echo "Deployment Failed!"   
   exit 1
fi

exit 0
