# Elmer User Tools Guide

## Overview

Elmer now supports user-defined tools! Instead of shipping with hardcoded tools, Elmer lets you create and configure your own tools that AI models can use. This gives you complete control over what tools are available while keeping Elmer focused on being a great relay system.

## Quick Start

1. **Create the tools directory:**
   ```bash
   mkdir -p ~/.elmer/tools
   ```

2. **Copy example tools:**
   ```bash
   cp /path/to/elmer/example-tools/*.json ~/.elmer/tools/
   ```

3. **Restart Elmer Mac app** to load the new tools

4. **Chat with an AI model** that supports function calling (like Llama 3.1, Qwen 2.5, etc.)

## How It Works

### The Architecture

1. **You define tools** in JSON files in `~/.elmer/tools/`
2. **Elmer loads** these definitions when it starts
3. **AI models** receive the tool definitions and can decide to use them
4. **Elmer executes** the tools on your Mac when requested
5. **Results** are sent back to the AI model to continue the conversation

### Tool Definition Format

Each tool is a JSON file with this structure:

```json
{
  "name": "tool_name",
  "description": "What this tool does",
  "parameters": {
    "type": "object",
    "properties": {
      "arg_name": {
        "type": "string",
        "description": "What this argument is for"
      }
    },
    "required": ["arg_name"]
  },
  "execution": {
    "type": "script",
    "command": "echo 'Hello {arg_name}'",
    "timeout": 30
  }
}
```

### Execution Types

#### Script Execution
```json
{
  "execution": {
    "type": "script", 
    "command": "your-command-here {arg}",
    "timeout": 30
  }
}
```

#### HTTP Requests
```json
{
  "execution": {
    "type": "http",
    "url": "https://api.example.com/endpoint", 
    "method": "POST",
    "timeout": 30,
    "headers": {
      "Content-Type": "application/json"
    }
  }
}
```

## Example Tools Included

- **current-time.json**: Get the current date and time
- **calculator.json**: Perform math calculations with bc
- **weather-wttr.json**: Get weather using wttr.in service
- **list-files.json**: List files in directories (safely restricted)
- **system-info.json**: Get basic Mac system information

## Security Features

Elmer includes several security measures:

- **Command validation**: Blocks dangerous commands (rm -rf, sudo, etc.)
- **Argument sanitization**: Prevents command injection
- **Timeout limits**: Maximum 5-minute execution time
- **Output limits**: Prevents memory exhaustion from large outputs
- **Restricted environment**: Clean environment variables
- **Safe PATH**: Only standard system paths

## Creating Your Own Tools

### Simple Example: Random Number Generator
```json
{
  "name": "random_number",
  "description": "Generate a random number between min and max",
  "parameters": {
    "type": "object",
    "properties": {
      "min": {"type": "integer", "description": "Minimum value"},
      "max": {"type": "integer", "description": "Maximum value"}
    },
    "required": ["min", "max"]
  },
  "execution": {
    "type": "script",
    "command": "echo $((RANDOM % ({max} - {min} + 1) + {min}))",
    "timeout": 5
  }
}
```

### API Integration Example: GitHub Stars
```json
{
  "name": "github_stars",
  "description": "Get the number of stars for a GitHub repository",
  "parameters": {
    "type": "object", 
    "properties": {
      "repo": {"type": "string", "description": "Repository in owner/name format"}
    },
    "required": ["repo"]
  },
  "execution": {
    "type": "http",
    "url": "https://api.github.com/repos/{repo}",
    "method": "GET",
    "timeout": 15,
    "headers": {
      "User-Agent": "Elmer-Tool"
    }
  }
}
```

## Best Practices

### Security
- Test commands manually before adding them as tools
- Use minimal permissions - avoid sudo/admin commands
- Set reasonable timeouts (5-30 seconds for most tools)
- Be careful with file operations and network requests

### Reliability  
- Handle errors gracefully in your commands
- Use absolute paths when possible
- Test with various inputs to ensure robustness
- Keep tool descriptions clear and specific

### Performance
- Use appropriate timeouts for your tools
- Avoid tools that produce huge outputs
- Consider caching for expensive operations

## Troubleshooting

### Tools Not Loading
- Check JSON syntax with `jsonlint` or similar
- Ensure files are in `~/.elmer/tools/` and end with `.json`
- Restart the Elmer Mac app after adding tools
- Check Console.app for error messages

### Tools Not Working
- Test the command manually in Terminal first
- Check file permissions on any scripts
- Verify all required parameters are defined
- Look for security warnings in the logs

### Models Not Using Tools
- Ensure you're using a function-calling capable model (Llama 3.1+, Qwen 2.5+, etc.)
- The model needs to be running through Elmer (not directly via ollama CLI)
- Some models need specific prompting to use tools effectively

## What's Different From Before

Previously, Elmer shipped with 5 hardcoded tools that you couldn't change. Now:

- ✅ **You control** what tools are available
- ✅ **Zero maintenance** burden on the Elmer developer
- ✅ **Extensible** - add any tool you want
- ✅ **Secure** - tools run in your environment with your permissions
- ✅ **No external dependencies** - tools use what you already have installed

This aligns with Elmer's philosophy of leveraging existing infrastructure rather than providing services.

## Support

If you have issues:
1. Check the example tools work first
2. Test your commands manually in Terminal
3. Verify JSON syntax
4. Check Console.app for error messages

Happy tool building! 🔧