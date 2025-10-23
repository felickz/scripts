<Query Kind="Program" />

void Main()
{
    // Settings
    var expression = @"[a-f0-9]{40}";
    var disallowedStartDelimiter = @"commit/|>>>>>>> ";
    var startDelimiter = @"[^a-zA-Z0-9-_+]";
    var endDelimiter = @"[^a-zA-Z0-9-_+]";

    // 1. Just the expression (for pure matches)
    var regex1 = new Regex(expression, RegexOptions.IgnoreCase);

    // 2. Start/End delimiters (expression surrounded by delimiters, no lookarounds)
    // We have to include the delimiters in the match, then extract the expression group.
    var regex2 = new Regex(
        $@"({startDelimiter})({expression})({endDelimiter})",
        RegexOptions.IgnoreCase
    );

    // 3. Delimiters or string boundaries (allow match if at start/end of string)
    var regex3 = new Regex(
        $@"((^|{startDelimiter})({expression})({endDelimiter}|$))",
        RegexOptions.IgnoreCase
    );

    // 4. Like #3 but explicitly excludes matches with disallowed start delimiters
    // We'll match the same as #3, and then filter in code based on disallowedStartDelimiter
    var regex4 = regex3;

    // Test string (edit to test edge cases)
    var test = "DD-APPLICATION-KEY=4e7f9c9b2a3d45c0a8e1b6f234cde123";

    "Regex 1 (Expression only):".Dump();
    foreach (Match m in regex1.Matches(test))
        m.Value.Dump();

    "Regex 2 (Delimited):".Dump();
    foreach (Match m in regex2.Matches(test))
        m.Groups[2].Value.Dump();

    "Regex 3 (Delimited or boundaries):".Dump();
    foreach (Match m in regex3.Matches(test))
        m.Groups[3].Value.Dump();

    "Regex 4 (Delimited/boundaries, disallowedStartDelimiter excluded):".Dump();
    foreach (Match m in regex4.Matches(test))
    {
        // Check if the preceding text matches the disallowedStartDelimiter
        var startIdx = m.Groups[3].Index;
        var preceding = test.Substring(0, startIdx);
        // Only check last chars up to length of longest disallowedStartDelimiter
        var maxLen = disallowedStartDelimiter.Split('|').Max(s => s.Length);
        var tail = preceding.Length >= maxLen ? preceding.Substring(preceding.Length - maxLen) : preceding;
        if (Regex.IsMatch(tail, "(" + disallowedStartDelimiter + ")$", RegexOptions.IgnoreCase))
            continue;
        m.Groups[3].Value.Dump();
    }
}