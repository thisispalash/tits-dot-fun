# Supra Code Generator MCP

Lean MCP integration for generating Supra Move contracts and TypeScript SDK code.

## Features

- **Move Contract Generation**: Production-ready contracts with security patterns
- **TypeScript SDK Generation**: Complete client code with examples
- **Supra Integration**: VRF, Automation, Oracles support
- **NFT Marketplace Patterns**: Based on production-ready templates

## Usage in Claude

Ask Claude to generate code:

```
Generate a Move contract for a DeFi lending protocol with VRF
```

```
Create TypeScript SDK code for an NFT marketplace with payments
```

## Available Features

- `vrf` - Supra VRF integration
- `automation` - Scheduled execution
- `oracles` - Price feeds and data
- `events` - On-chain event emission
- `payments` - Token transfers

## Manual Setup

If auto-config failed, add to Claude Desktop config:

```json
{
  "mcpServers": {
    "supra-code-generator": {
      "command": "node",
      "args": ["/path/to/supra-code-gen/build/index.js"]
    }
  }
}
```

Restart Claude Desktop after configuration.
