az devops login --organization https://dev.azure.com/octodemo-temporary  
az devops configure --defaults organization=https://dev.azure.com/octodemo-temporary project="GHAzDO Trial Board Setup"
az devops project list  
az boards work-item show --id 31  
