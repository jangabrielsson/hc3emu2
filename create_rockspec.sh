#!/bin/bash
# Pushrock - A simple script to create the rock...
readonly TEMPLATE="rockspecs/hc3emu2-template.rockspec"
rock_file=$(echo ${TEMPLATE} | sed "s/template/${1}/")
cp ${TEMPLATE} ${rock_file}
# change {{VERSION}} in the file to the new version, argument 1
sed -i "" "s/{{VERSION}}/${1}/g" ${rock_file}
echo "Pushrock - ${rock_file}"

git add ${rock_file}
git commit -m "Update ${rock_file} to version ${1}"
git push origin main  # Push the commit to remote (assuming 'main' branch)
git tag -a v${1} -m "Version ${1}"
git push origin v${1}