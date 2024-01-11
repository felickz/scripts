<Query Kind="Statements">
  <NuGetReference>Microsoft.TeamFoundationServer.Client</NuGetReference>
  <NuGetReference>Microsoft.TeamFoundationServer.ExtendedClient</NuGetReference>
  <NuGetReference>Microsoft.VisualStudio.Services.Client</NuGetReference>
  <Namespace>Microsoft.TeamFoundation.SourceControl.WebApi</Namespace>
  <Namespace>Microsoft.VisualStudio.Services.Common</Namespace>
  <Namespace>Microsoft.VisualStudio.Services.WebApi</Namespace>
  <RuntimeVersion>6.0</RuntimeVersion>
</Query>

//Sample from: https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/dotnet-client-libraries?view=azure-devops&viewFallbackFrom=vsts


 string collectionUri = "https://dev.azure.com/octodemo-felickz";
 string projectName = "csharp-synthetics";
 string repoName = "WebGoat.NET7";
 string pat = Util.GetPassword("azdo-octodemo-felickz-pat");



var creds = new VssBasicCredential(string.Empty, pat);

// Connect to Azure DevOps Services
var connection = new VssConnection(new Uri(collectionUri), creds);

// Get a GitHttpClient to talk to the Git endpoints
using var gitClient = connection.GetClient<GitHttpClient>();

// Get data about a specific repository			
var repo = gitClient.GetRepositoryAsync(projectName, repoName).Result;
repo.Dump();
