#!/usr/bin/env bash

changedfilenames=$1                # get data as below
IncludeDestructiveChanges="$2"     # true or false
declare -a MetaToExclude="$3"      # e.g. appmenus
declare -a MetaNamesToExclude="$4" # e.g. 'metadata appmenus'
EnvironmentUserName="$5"           # e.g. ian.burton@sgbd.co.uk.qa
sourceBranch="$6"                  # get code of source branch to get diff of fields changed for object type files
targetBranch="$7"                  # get code of target branch to get diff of fields changed for object type files
PackageVersion="$8"
TEMP_BRANCH="$9"
set -x

# Declare variables
declare -A packageMap
declare -A destructivePackageMap

exclusionFlag=1
FileStatus=""
operation=""
objectname=""
result=""
#extension=""
#filename=""

echo "Describe Metadata"
sfdx force:mdapi:describemetadata -f metadescribe.json -u $EnvironmentUserName
# .object = CustomObject

echo "list the folder and files"
# ls -ltr ./*
getfilesuffix() {
        # returns only the file suffix after last dot. eg. Account.(object)
        fullfilename=$1
        echo "${fullfilename##*.}"
}

getfilename() {
        # returns only the file name before the last dot eg. (Account).object
        fullfilename=$1
        echo "${fullfilename%.*}"
}

getfiletype() {
        #returns the type of file
        filetype=$1
        echo "$(cut -d/ -f2 <<<"$filetype")"
}

getObjects() {
        directoryName=$1
        suffix=$2
        result=$(jq '.metadataObjects[] | select (.directoryName=="'"$1"'" and .suffix=="'"$2"'") .xmlName' metadescribe.json | tr -d '"')
        if [[ $result == "" ]]; then
                result=$(jq '.metadataObjects[] | select (.directoryName=="'"$1"'") .xmlName' metadescribe.json | tr -d '"')
        fi
        echo $result
}

exclusionCheck() {
        exclusionFlag=1
        file="$1"
        #file=$(echo $file | sed 's/[ \t]*$//')
        file=$(echo $file | xargs echo -n)
        # its a changed file, so lets see if its a delete or edit/add
        fullfilename="$(echo ${file} | sed -r 's|([^/]*/){2}||')"
        #extension="${filename##*.}"
        extension=$(getfilesuffix "${fullfilename}")
        #filename="${fullfilename%.*}"
        filename=$(getfilename "${fullfilename}")
        #filetype=$(getfiletype "${file}")
        filetype="$(cut -d/ -f2 <<<"${file}")"
        #filetype="${file}" | cut -d/ -f2
        folder=$(basename $(dirname "${file}"))
        #echo "$filetype"
        metafileType=$(getObjects "${filetype}" "${extension}")
        if [[ $metafileType == "" ]]; then
                echo $filetype" not found in metamapping" >&2
        fi
        #filetypeIsExcluded=$(array_contains2 MetaToExclude "${filetype}")
        #echo "META ${filetype} TO EXCLUDE filetypeIsExcluded="$filetypeIsExcluded
        filetypeIsExcluded=0

        for element in "${MetaToExclude[@]}"; do

                echo "element is" $element "filetype is" $filetype >&2
                echo ${element,,}${filetype,,} >&2

                if [ "${element,,}" == "${filetype,,}" ]; then
                        filetypeIsExcluded=1
                        echo "${filetype} is excluded!!" >&2
                        break
                fi
        done

        # This looks for MetaTypes to exclude (e.g. objects, class etc.)
        #^$str1$str1($str2|)$
        pattern="^${filetype}$"
        if [[ "${MetaToExclude[@]}" =~ $pattern ]]; then
                # means this item needs to be excluded
                filetypeIsExcluded=1
                echo "${filetype} is excluded!!" >&2
        fi

        # This excludes MetaNames (one or more of a type)
        filenameIsExcluded=0
        for element in "${MetaNamesToExclude[@]}"; do
                echo "element is" $element "filename is" $filename >&2
                echo ${element,,}${filename,,} >&2
                if [ "${element,,}" == "${filename,,}" ]; then
                        filenameIsExcluded=1
                        echo "${filename} filename is excluded!!" >&2
                        break
                fi
        done

        #^$str1$str1($str2|)$
        fnpattern="^${filename}$"
        if [[ "${MetaNamesToExclude[@]}" =~ $fnpattern ]]; then
                # means this item needs to be excluded
                filenameIsExcluded=1
                echo "${filename} is excluded!!" >&2
        fi
        if [[ $filetypeIsExcluded -eq 0 ]] && [[ $filenameIsExcluded -eq 0 ]]; then
                exclusionFlag=0
        fi
}
# This will add customLabels by going through the whole CustomLabels.labels file
# and adding everything in there for the deploy
customLabels() {
        mkdir -p deployPackage"/"$(dirname "${file}") && cp -p "${file}" "deployPackage/${file}"
        grep -e '<fullName>' $file >customLabels.txt
        customLabels=$(sed -n 's:.*<fullName>\(.*\)</fullName>.*:\1:p' customLabels.txt)
        for label in $customLabels; do
                packageitemlist=${packageMap["CustomLabel"]}
                if [[ "$packageitemlist" =~ *"<members>""$label""</members>"* ]]; then
                        echo "This folder item is already in the list"
                else
                        packageMap["CustomLabel"]+="<members>""$label""</members>"
                fi
        done
}

addObject() {
        echo "[echo] Ready to Add or Modify"
        echo "Extension is: $extension"
        echo "Filename is: $filename"
        echo "File is: $file"
        # Is this a custom label?
        if [[ "$filename" == "CustomLabels" ]]; then
                customLabels
        else
                set -x
                if [[ "$extension" == *"xml" ]] && [[ "$filename" != "package.xml" ]]; then

                        #echo "just copy file"$extension
                        echo "[echo] currect directory is: $PWD"
                        mkdir -p deployPackage"/"$(dirname "${file}") && cp -p "${file}" "deployPackage/${file}"
                        # there is a rare case that the meta.xml was changed (version number) and the main code file needs to be added
                        if [[ ${file} == *"-meta.xml"* ]]; then
                                #make sure to also copy the file for this meta file even if its not changed
                                #filename="$(echo ${filename%.*} | sed 's|-meta||g')"
                                filename="${filename%.*}"
                                newfilepath=${file%-*}
                                newfilename=${filename%-*}
                                echo $newfilename"-NEWFILENAME"
                                echo $packageMap["$metafileType"]
                                packageitemlist=${packageMap["$metafileType"]}
                                #echo $packageitemlist
                                # it might be an aura item, then the filename needs to be the folder name
                                # $folder
                                packagefilename=""
                                if [[ "$filetype" == "aura" ]] || [[ "$filetype" == "lwc" ]]; then
                                        packagefilename=$folder
                                else
                                        if [[ "$filetype" == "dashboards" ]] || [[ "$filetype" == "reports" ]]; then
                                                echo "====================filename is: $filename"
                                                echo "I am inside dashbaord"
                                                packagefilename=${filename%-*}
                                                echo "=====================packagefilename is: $packagefilename"
                                        else
                                                packagefilename=$filename
                                        fi
                                fi
                                if [[ "$filetype" != "email" ]]; then # dont want to add meta files to the package xml
                                        if [[ "$packageitemlist" =~ "<members>"$packagefilename"</members>" ]]; then
                                                echo "This xml item is already in the list"
                                        else
                                                echo "adding to package unique"
                                                packageMap["$metafileType"]+="<members>"$packagefilename"</members>"
                                        fi
                                fi
                                echo "[echo] currect directory is: $PWD"
                                echo "[echo] SRC directory is:"
                                # ls -ltr src
                                echo "[echo]  deployPackage directory is:"
                                # ls -ltr deployPackage
                                cp -p "${newfilepath}" "deployPackage/${newfilepath}" #validate this line for src/dashboards/For_Management
                                # but if the meta file for a aura or lwc file have change, we need all the folder contents
                                if [[ "$filetype" == "aura" || "$filetype" == "lwc" ]]; then
                                        # also copy the entire contents of the aura or lwc folder (even if the file hasnt changed)
                                        echo "copy the entire folder if its aura or lwc if metaxml changed"
                                        compfolder=$(dirname "${file}")
                                        echo "compfolder "$compfolder
                                        cp -r -n ./$compfolder "./deployPackage/src/$filetype/"
                                fi
                                # ls -ltr "./deployPackage/src/$filetype/"
                        fi

                else
                        #echo "adding to packagemap - <members>"$filename"</members>"
                        mkdir -p deployPackage"/"$(dirname "${file}") && cp -p "${file}" "deployPackage/${file}"
                        echo "[echo] SRC directory is:"
                        # ls -ltr src
                        echo "[echo]  deployPackage directory is:"
                        # ls -ltr deployPackage
                        # but if its a class or trigger file, we need to include the meta xml file
                        if [[ "$extension" == "cls" ]] || [[ "$extension" == "trigger" ]] || [[ "$extension" == "email" ]] || [[ "$extension" == "js" ]] || [[ "$extension" == "cmp" ]]; then
                                echo "Copying class or component meta file"
                                cp -p "${file}""-meta.xml" "deployPackage/${file}""-meta.xml"
                        fi
                        echo "metafileType is "$metafileType
                        packageitemlist=${packageMap["$metafileType"]}
                        #echo $packageitemlist
                        #------------------ NEW CODE BEGIN ---------------------
                        echo "Debug Extension is:"
                        echo $extension
                        echo "Filename"$filename
                        pwd
                        #Deletion of flows
                        if [[ $extension == "flow" ]]; then
                                git fetch
                                git diff --unified=0 origin/${targetBranch}..${TEMP_BRANCH} -- $file >${filename}-filediff.txt
                                echo ${filename}-filediff.txt
                                echo "Catting ${filename}-filediff.txt"
                                cat ${filename}-filediff.txt
                                # Let's grep for a deleted field by '^- *<fullName>' and then searching for '<fields> in the line above that
                                #poss_del_file=$(grep -B 1 '^- *<fullName>' ${filename}-filediff.txt | grep -C 1 '<fields>' | awk -F'>' '/fullName/ {print $2}' | awk -F'<' '{print $1 }')
                                #poss_del=$poss_del_file
                                # poss_del_recordTypes=$(grep -B 1 '^- *<fullName>' ${filename}-filediff.txt | grep -C 1 '<recordTypes>' | awk -F'>' '/fullName/ {print $2}' | awk -F'<' '{print $1 }')
                                # poss_del=$poss_del_recordTypes
                                echo "poss_del is: ${filename}"
                                # if $poss_del is not empty continue to look for the fullName with a + in a git field or recordType
                                if [[ -n "$filename" ]]; then
                                        echo "Possibly removed items are: $filename"
                                        # This loop looks for the fullName with a + in a git field or recordType. This means the code have been added somewhere else
                                        # for line in $poss_del
                                        # do
                                        # grep "^+ .*<fullName>$line</fullName>" ${filename}-filediff.txt > /dev/null
                                        # if [ $? -eq 0 ]; then
                                        #        echo "$line was moved not removed"
                                        # else
                                        #      echo "$line was removed, add it to destructivePackage file"
                                        #delfieldname="$line"
                                        #  fieldmetafileType="CustomField"
                                        # pseudocode
                                        # if this is a field:
                                        #        fieldmetafileType="CustomField"
                                        # fi
                                        # if this is a recordType:
                                        #         fieldmetafileType="recordTypes"
                                        # fi
                                        # add it to the destructivepackageMap
                                        #if [[ "$delpackageitemlist" =~ *"<members>${filename}.${line}</members>"* ]]; then
                                        if [[ "$delpackageitemlist" =~ *"<members>${filename}</members>"* ]]; then
                                                echo "This deleted field is already in the list"
                                        else
                                                #destructivePackageMap[$fieldmetafileType]+="<members>${filename}.${line}</members>"
                                                destructivePackageMap[$fieldmetafileType]+="<members>${filename}</members>"
                                        fi
                                        #fi
                                        #done
                                else
                                        echo "poss_del	is empty"
                                fi
                        fi # if extension = object closed here.
                        # flows deletion ends here

                        if [[ "$extension" == "object" ]]; then
                                git fetch
                                git diff --unified=0 origin/${targetBranch}..${TEMP_BRANCH} -- $file >${filename}-filediff.txt
                                echo ${filename}-filediff.txt
                                echo "Catting ${filename}-filediff.txt"
                                cat ${filename}-filediff.txt
                                # Let's grep for a deleted field by '^- *<fullName>' and then searching for '<fields> in the line above that
                                poss_del_field=$(grep -B 1 '^- *<fullName>' ${filename}-filediff.txt | grep -C 1 '<fields>' | awk -F'>' '/fullName/ {print $2}' | awk -F'<' '{print $1 }')
                                poss_del=$poss_del_field
                                # poss_del_recordTypes=$(grep -B 1 '^- *<fullName>' ${filename}-filediff.txt | grep -C 1 '<recordTypes>' | awk -F'>' '/fullName/ {print $2}' | awk -F'<' '{print $1 }')
                                # poss_del=$poss_del_recordTypes
                                echo "poss_del is: ${poss_del}"
                                # if $poss_del is not empty continue to look for the fullName with a + in a git field or recordType
                                if [[ -n "$poss_del" ]]; then
                                        echo "Possibly removed items are: $poss_del"
                                        # This loop looks for the fullName with a + in a git field or recordType. This means the code have been added somewhere else
                                        for line in $poss_del; do
                                                grep "^+ .*<fullName>$line</fullName>" ${filename}-filediff.txt >/dev/null
                                                if [ $? -eq 0 ]; then
                                                        echo "$line was moved not removed"
                                                else
                                                        echo "$line was removed, add it to destructivePackage file"
                                                        #delfieldname="$line"
                                                        fieldmetafileType="CustomField"
                                                        # pseudocode
                                                        # if this is a field:
                                                        #        fieldmetafileType="CustomField"
                                                        # fi
                                                        # if this is a recordType:
                                                        #         fieldmetafileType="recordTypes"
                                                        # fi
                                                        # add it to the destructivepackageMap
                                                        if [[ "$delpackageitemlist" =~ *"<members>${filename}.${line}</members>"* ]]; then
                                                                echo "This deleted field is already in the list"
                                                        else
                                                                destructivePackageMap[$fieldmetafileType]+="<members>${filename}.${line}</members>"
                                                        fi
                                                fi
                                        done
                                else
                                        echo "poss_del	is empty"
                                fi
                        fi # if extension = object closed here.
                        #------------------ NEW CODE ENDS ---------------------
                        # and if its a report, then we need to include the report folder in the package
                        if [[ "$extension" == "report" ]] || [[ "$filetype" == "email" ]] || [[ "$extension" == "dashboard" ]]; then
                                echo "its a "$filetype
                                if [[ "$packageitemlist" =~ *"<members>""$filename""</members>"* ]]; then
                                        echo "This folder item is already in the list"
                                else
                                        packageMap["$metafileType"]+="<members>""$filename""</members>"
                                fi
                        else
                                # it might be an aura item, then the filename needs to be the folder name
                                # $folder
                                packagefilename=""
                                if [[ "$filetype" == "aura" || "$filetype" == "lwc" ]]; then
                                        packagefilename=$folder
                                        # also copy the entire contents of the aura or lwc folder (even if the file hasnt changed)
                                        echo "copy the entire folder if its aura or lwc"
                                        compfolder=$(dirname "${file}")
                                        echo "compfolder "$compfolder
                                        cp -r -n ./$compfolder "./deployPackage/src/$filetype/"
                                else
                                        #packagefilename=$(echo $filename | sed 's|-meta||g')
                                        packagefilename="$filename"
                                fi
                                if [[ "$packageitemlist" =~ *"<members>"$packagefilename"</members>"* ]]; then
                                        echo "This normal item is already in the list"
                                else
                                        packageMap[$metafileType]+="<members>"$packagefilename"</members>"
                                fi
                                # ls -ltr "./deployPackage/src/$filetype/"
                        fi
                fi
        # This fi closes off the if to check for customLabels
        fi
}

removeObject() {
        echo "[echo] Ready to remove"
        # This code checks firstly for aura component, or an lwc component. These are handled differently
        # by salesforce - they have to have the directory name, instead of the file name. Also an aura
        # must have had the .cmp file deleted, and the lwc must have had the .js file deleted. If that's
        # the case, we can delete the whole component.

        # only if we want destructive changes
        #lets add it to the desctructive changes (there will be no file to copy, since its deleted)
        delpackageitemlist=${destructivePackageMap["$metafileType"]}
        #echo $delpackageitemlist
        if [[ "$extension" != *"xml" ]] && [[ "$filename" != "package.xml" ]]; then
                #filter out duplicates
                if [[ "$delpackageitemlist" =~ "<members>"$filename"</members>" ]]; then
                        echo "This xml item is already in the list"
                elif [[ "$filetype" == "aura" ]]; then
                        aura_path=$(echo $folder | awk -F '/' '{ print $1 }')
                        if [[ "$delpackageitemlist" =~ "<members>"$aura_path"</members>" ]]; then
                                echo "This xml item is already in the list"
                        elif [[ "$extension" == *"cmp" ]]; then
                                destructivePackageMap[$metafileType]+="<members>"$aura_path"</members>"
                        fi
                elif [[ "$filetype" == "lwc" ]] && [[ $extension == *"js" ]]; then
                        lwc_path=$(echo $folder | awk -F '/' '{ print $1 }')
                        if [[ "$delpackageitemlist" =~ "<members>"$lwc_path"</members>" ]]; then
                                echo "This xml item is already in the list"
                        elif [[ $extension == *"js" ]]; then
                                destructivePackageMap[$metafileType]+="<members>"$lwc_path"</members>"
                        fi
                else
                        # This destructive change is for anything that is not aura or lwc:
                        echo "adding to destructive package unique"
                        if [[ "$filetype" != "aura" ]] && [[ "$filetype" != "lwc" ]]; then
                                destructivePackageMap[$metafileType]+="<members>"$filename"</members>"
                        fi
                fi
        fi
}

# Entrypoint
#start with reading diff file line by line

while IFS= read -r line; do
        #process each line at a time
        operation=$(echo $line | awk -F ' ' '{print $1}')
        if [[ "${operation:0:1}" != 'R' ]]; then
                objectname=$(echo $line | sed -n 's/\([^ \t]*\)\(.*$\)/\2/p' | sed -e 's/^[ \t]*//')
                echo "filename is: $objectname"
        else
                objectname=$(echo $line | sed 's/.*\(src.*\)\(src.*\)/\1/')
                echo "filename is: $objectname"
        fi

        #remove first entry, set variables for addtion of second object
        if [[ "${operation:0:1}" == 'R' ]]; then
                exclusionCheck "${objectname}"
                if [ "$exclusionFlag" -eq 0 ]; then
                        echo "[echo] calling Remove or Delete object function"
                        removeObject
                else
                        echo "NOT deploying this item: $filetype"
                        #break; Not needed, Although remove is excluded, next fileype will proceed for execution.
                fi
                operation="A"
                objectname=$(echo $line | sed 's/.*\(src.*\)\(src.*\)/\2/')
        fi

        #exclusionFlag=$(exclusionCheck "${objectname}")
        exclusionCheck "${objectname}"
        #call respective functions based on operation
        if [ "$exclusionFlag" -eq 0 ]; then
                if [[ "$operation" == 'D' ]]; then
                        if [[ "$IncludeDestructiveChanges" = true ]]; then
                                echo "[echo] calling Remove or Delete object function"
                                removeObject
                        else
                                echo "[echo] Don't add in destructive changes for: $filetype"
                        fi
                elif [[ "${operation:0:1}" == 'R' ]]; then
                        echo "[echo] calling Remove or Delete object function"
                        removeObject
                else
                        echo "[echo] calling Add or Modify object function"
                        addObject
                fi
        else
                echo "NOT deploying this item: $filetype"
        fi
done <$changedfilenames

#process the output files now
destructiveString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><Package xmlns=\"http://soap.sforce.com/2006/04/metadata\">"
packageString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><Package xmlns=\"http://soap.sforce.com/2006/04/metadata\">"
echo "Starting to build package.xml"

for line in "${!packageMap[@]}"; do
        packageString+="<types>${packageMap["$line"]}<name>"$line"</name></types>"
done

destructivecount=0
for line in "${!destructivePackageMap[@]}"; do
        destructiveString+="<types>${destructivePackageMap["$line"]}<name>"$line"</name></types>"
        ((destructivecount += 1))
done

destructiveString+="<version>$PackageVersion</version></Package>"
packageString+="<version>$PackageVersion</version></Package>"

echo $packageString >deployPackage/src/package.xml
#
if [[ $destructivecount > 0 ]]; then
        echo $destructiveString >deployPackage/src/destructiveChangesPost.xml
fi

tar -zcvf package.tar.gz deployPackage/src
