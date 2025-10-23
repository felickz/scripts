<Query Kind="Statements" />

//.net 8 / C# 12 language feature: collection expressions https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12#collection-expressions

int[] mynumbers = [];

// Array initialization
int[] numbers = [1, 2, 3, 4, 5];

// List initialization
List<string> fruits = ["apple", "banana", "orange"];
List<string> myfruits = [];

Dictionary<string, string> fruitdict = new Dictionary<string, string> { { "apple", "banana" } };
Dictionary<string, string> fruitdictEmpty = [];


// Span initialization
Span<int> ages = [25, 30, 35, 40];

// Spreading elements from another collection
int[] moreNumbers = [..numbers, 6, 7, 8];

// Multiple spreads
//var combined = [.. fruits, "mango", .. ["pear", "grape"]];