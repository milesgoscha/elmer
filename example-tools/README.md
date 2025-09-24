# Elmer Tool Examples

This directory contains example tool definitions that you can use with Elmer. To use these tools:

1. Copy the desired `.json` files to `~/.elmer/tools/`
2. Restart your Elmer Mac app to load the new tools
3. The tools will now be available when chatting with AI models that support function calling

## Available Example Tools

### current-time.json
Gets the current date and time using the system `date` command.

**Usage:** "What time is it?"

### calculator.json
Performs mathematical calculations using the `bc` calculator.

**Usage:** "What's 2+2?" or "Calculate the square root of 144"

### weather-wttr.json
Gets weather information using the free wttr.in service (no API key required).

**Usage:** "What's the weather in San Francisco?"

### list-files.json
Lists files in directories relative to your home directory.

**Usage:** "Show me the files in my Documents folder"

### system-info.json
Shows basic system information about your Mac.

**Usage:** "Tell me about my system"

## Creating Your Own Tools

### Script-based Tools
Tools can execute shell commands/scripts:

```json
{
  "name": "my_tool",
  "description": "Description of what this tool does",
  "parameters": {
    "type": "object",
    "properties": {
      "arg1": {
        "type": "string",
        "description": "Description of argument"
      }
    },
    "required": ["arg1"]
  },
  "execution": {
    "type": "script",
    "command": "echo 'Hello {arg1}'",
    "timeout": 30
  }
}
```

### HTTP-based Tools
Tools can also make HTTP requests:

```json
{
  "name": "api_tool",
  "description": "Call an API endpoint",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Search query"
      }
    },
    "required": ["query"]
  },
  "execution": {
    "type": "http",
    "url": "https://api.example.com/search",
    "method": "POST",
    "timeout": 30,
    "headers": {
      "Content-Type": "application/json",
      "Authorization": "Bearer your-api-key-here"
    }
  }
}
```

## Security Notes

- Tools run with your user permissions
- Be careful with scripts that modify files or system settings
- Consider using timeouts to prevent hanging
- Test tools manually before using with AI models
- Keep API keys secure and don't commit them to version control

## Troubleshooting

If tools aren't working:

1. Check the Elmer Mac app console for error messages
2. Test the command manually in Terminal
3. Verify JSON syntax is correct
4. Ensure required parameters are defined
5. Check file permissions on scripts

## Contributing

Feel free to create more example tools and share them with the community!