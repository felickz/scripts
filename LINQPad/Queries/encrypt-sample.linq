<Query Kind="Program">
  <Namespace>System.Security.Cryptography</Namespace>
</Query>

void Main()
{
}

public class Program
{
    public static void Main()
    {
        string encryptedString = "SGVsbG8gd29ybGQ="; // This should be your AES encrypted, Base64 encoded string
        byte[] encryptedBytes = Convert.FromBase64String(encryptedString);

        byte[] key = Encoding.UTF8.GetBytes("your-encryption-key"); // Replace with your key
        byte[] iv = Encoding.UTF8.GetBytes("your-initialization-vector"); // Replace with your IV

        using (AesCryptoServiceProvider aes = new AesCryptoServiceProvider())
        {
            aes.Key = key;
            aes.IV = iv;
            ICryptoTransform decryptor = aes.CreateDecryptor(aes.Key, aes.IV);

            using (MemoryStream msDecrypt = new MemoryStream(encryptedBytes))
            {
                using (CryptoStream csDecrypt = new CryptoStream(msDecrypt, decryptor, CryptoStreamMode.Read))
                {
                    using (StreamReader srDecrypt = new StreamReader(csDecrypt))
                    {
                        string decryptedString = srDecrypt.ReadToEnd();
                        Console.WriteLine(decryptedString);
                    }
                }
            }
        }
    }
}