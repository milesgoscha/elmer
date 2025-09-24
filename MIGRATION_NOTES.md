# Migration Notes: User-Defined Tools

## What Changed

Elmer has migrated from **hardcoded tools** to **user-defined tools** to better align with the project philosophy of leveraging existing infrastructure rather than providing services.

## Before (v1.x)
- 5 hardcoded tools shipped with Elmer
- Tools executed on both iOS and Mac
- Required maintenance of external APIs (web search, etc.)
- Users couldn't add or modify tools

## After (v2.x) 
- **Zero hardcoded tools** - users define their own
- Tools execute only on Mac (where they belong)
- **No external dependencies** - users bring their own APIs/commands
- **Fully customizable** - users control everything

## Migration Steps

### For Users
1. **Copy example tools**:
   ```bash
   mkdir -p ~/.elmer/tools
   cp example-tools/*.json ~/.elmer/tools/
   ```

2. **Restart Elmer Mac app** to load tools

3. **No iOS app changes needed** - tools are handled server-side

### For Developers
The old tool system has been completely removed:

#### Files Removed
- ✅ `ToolRegistry.swift` - Hardcoded tool definitions
- ✅ Tool implementations in iOS `SecureAPIClient.swift`

#### Files Added
- ✅ `UserToolManager.swift` - Reads user-defined tools
- ✅ Example tool definitions in `example-tools/`
- ✅ `USER_TOOLS_GUIDE.md` - Complete user documentation

#### Key Changes
- `CloudKitRelayManager` now uses `UserToolManager` instead of `ToolRegistry`
- iOS `ChatView` no longer attempts client-side tool execution
- All tools execute on Mac where they have proper system access
- Comprehensive error handling ensures iOS always gets responses

## Benefits

1. **Zero Maintenance**: No hardcoded tools to maintain
2. **No External Costs**: Users provide their own API keys/services  
3. **Infinite Extensibility**: Users can add any tool they want
4. **Better Security**: Tools run in user's environment with their permissions
5. **Philosophy Alignment**: Tool enabler, not tool provider

## Compatibility

- **Existing conversations**: Continue to work (no tools available until user adds them)
- **API compatibility**: CloudKit relay protocol unchanged
- **iOS app**: No changes needed, works automatically

## Support

Users experiencing issues should:
1. Check `~/.elmer/tools/` directory exists and contains `.json` files
2. Verify JSON syntax with a validator
3. Test commands manually in Terminal
4. Check Console.app for error messages
5. Reference `USER_TOOLS_GUIDE.md` for examples

The migration maintains all existing functionality while giving users complete control over their tool ecosystem.