
# Calculate the date 7 days ago
$daysAgo = (Get-Date).AddDays(-7)
$markdownLinks = $null 
# Loop through 10 pages of the GitHub Changelog Atom feed until we find an entry published more than $daysAgo
for ($i = 1; $i -le 10; $i++) {
    # Construct the URL for the current page
    $url = "https://github.blog/changelog/all.atom?paged=$i"
    
    # Load the Atom feed from the current page
    $feed = Invoke-WebRequest -Uri $url
    
    # Create an XmlDocument object and load the feed into it
    $xml = New-Object -TypeName System.Xml.XmlDocument
    $xml.LoadXml($feed.Content)
    
    # Loop over each entry and extract the title, id, and published date
    foreach ($entry in $xml.feed.entry) {
        $title = $entry.title."#cdata-section"
        $id = $entry.id

        $published = [datetime]::Parse($entry.published)
        if ($published -lt $daysAgo) {
            # We've found an entry published more than x days ago, so exit the loop
            break
        }
        if ($title -match "security|dependabot|secret|code scanning|codeql|dependency") {
            $markdownLinks += "- $($published.ToString('MMM dd')) - [$title]($id)`n"
        }
    }
}

#Write-Output $markdownLinks
Write-Output "MARKDOWN=`"$($markdownLinks)`"" 


