#!/bin/bash

failed=0
for yamlTemplate in $(find ./charts -regex '^\.\/charts\/.*\/templates\/[^\/]*.*\/*.*\.yaml'); do
  kind=$(cat $yamlTemplate | grep -e '^kind:' | awk '{ printf("%s\n", $2) }' |  tr '[:upper:]' '[:lower:]')
  
  case "$yamlTemplate" in
  *"./charts/fabconnect"*)
      # Ignore the fabconnect charts as they may be from external repo
    ;;
    *)
      if ! cat $yamlTemplate | grep "$(cat ./charts/license.tpl)"  > /dev/null; then
        echo "ERROR: $yamlTemplate filename does not start with the license"
        failed=$(($failed+1))
      fi
    ;;
  esac
done

if [[ $failed -gt 0 ]]; then
  exit 1
fi
