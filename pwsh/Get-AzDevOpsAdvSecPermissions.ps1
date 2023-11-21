# bit field: 131072
az devops security permission namespace list | jq '.[] | select(.name=="Git Repositories") | .actions[] | select(.name=="DismissAdvSecAlerts") | .bit'



#"ViewAdvSecAlerts = 65536"
#"DismissAdvSecAlerts = 131072"
#"ManageAdvSecScanning = 262144"
az devops security permission namespace list | jq '.[] | select(.name=="Git Repositories") | .actions[] | select(.name | contains("AdvSec")) | "\(.name) = \(.bit)"'
