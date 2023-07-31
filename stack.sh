echo "docker compose -p $1\\"
shift # remove first argument from arglist

# when disabling certain composes, we can put them in a folder
# called "disabled"
# ** will only match one level of directories
# so, the folders inside "disabled" will be ignored

for compose in **/docker-compose.yml; do echo "  -f $compose \\"; done
echo "  --env-file .env \\"
for env in **/.env; do echo "  --env-file $env \\"; done
echo "  ${@}" # print remaining arguments
