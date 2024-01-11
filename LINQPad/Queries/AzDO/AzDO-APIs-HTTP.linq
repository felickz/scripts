<Query Kind="Statements">
  <NuGetReference>Newtonsoft.Json</NuGetReference>
  <Namespace>System.Net.Http</Namespace>
  <Namespace>System.Net.Http.Headers</Namespace>
  <Namespace>Newtonsoft.Json.Linq</Namespace>
</Query>


try
{
	var organization = "octodemo-felickz";
	var project = "csharp-synthetics";		
	var MAPPED_ADO_PAT = Util.GetPassword("azdo-octodemo-felickz-pat");

	//	var organization = "octodemo-temporary";
	//	var project = "Space In Name";
	//	var MAPPED_ADO_PAT = Util.GetPassword("azdo-octodemo-temporary-pat");

	string projectId; // will be looked up
	using (HttpClient client = new HttpClient())
	{
		client.DefaultRequestHeaders.Accept.Add(new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("application/json"));
		client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(System.Text.ASCIIEncoding.ASCII.GetBytes(string.Format("{0}:{1}", "", MAPPED_ADO_PAT))));
		using (HttpResponseMessage response = client.GetAsync($"https://dev.azure.com/{organization}/_apis/projects").Result)
		{
			response.EnsureSuccessStatusCode();
			string responseBody = await response.Content.ReadAsStringAsync();
			Console.WriteLine($"Projects response {(int)response.StatusCode} {response.StatusCode}({response.RequestMessage.RequestUri}):\n");
			Console.WriteLine(responseBody);			
			projectId = (((JArray)JObject.Parse(responseBody)["value"]).First(o => string.Equals(o["name"]?.Value<string>(), project, StringComparison.OrdinalIgnoreCase))?["id"]).ToString();
			Console.WriteLine($"\nProject id for '{project}': {projectId} \n");
		}			

		using (HttpResponseMessage response = client.GetAsync($"https://dev.azure.com/{organization}/{projectId}/_apis/git/repositories").Result)
		{
			response.EnsureSuccessStatusCode();
			string responseBody = await response.Content.ReadAsStringAsync();
			Console.WriteLine($"\nRepos response {(int)response.StatusCode} {response.StatusCode}({response.RequestMessage.RequestUri}):\n");
			Console.WriteLine(responseBody);
		}
	}
}
catch (Exception ex)
{
	Console.WriteLine(ex.ToString());
}
