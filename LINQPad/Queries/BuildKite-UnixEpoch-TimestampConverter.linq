<Query Kind="Program" />

// BuildKite logs with unix epoch timestamp
// - replace any timestamp strings _bk;t=1710814013648 and extract out the t=### in unix format 
// - with this format "2024-03-11T21:32:00.5140622Z"
void Main()
{

	string fileName = @"C:\Users\chadbentz\OneDrive - Microsoft\Customers\Anchorage\run-codeql-analysis_build_333_go-analysis.log";
	string tempFileName = Path.GetTempFileName();

	using (var reader = new StreamReader(fileName))
	using (var writer = new StreamWriter(tempFileName))
	{
		string line;
		while ((line = reader.ReadLine()) != null)
		{
			var match = Regex.Match(line, @"_bk;t=(\d+)");
			if (match.Success)
			{
				long unixTime = long.Parse(match.Groups[1].Value);
				DateTime dateTime = DateTimeOffset.FromUnixTimeMilliseconds(unixTime).UtcDateTime;
				string newTimestamp = dateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")+ " ";
				line = line.Replace(match.Value, newTimestamp);
			}
			writer.WriteLine(line);
		}
	}

	File.Delete(fileName);
	File.Move(tempFileName, fileName);

}


