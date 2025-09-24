
Name: Notion
Description: All-in-one workspace for notes, docs, and project management.
Type: streamableHttp
URL: https://mcp.notion.com/mcp

Name: Figma
Description: Design and collaboration platform for teams.
Type: streamableHttp
URL: http://127.0.0.1:3845/mcp

Name: Linear
Description: Issue tracking and project management for development teams.
Type: streamableHttp
URL: https://mcp.linear.app/sse

Name: GitHub
Description:Version control and collaborative development platform.
Type: stdio
Command: docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
Environment Variables: GITHUB_PERSONAL_ACCESS_TOKEN = VARIABLE VALUE

Name: Playwright
Description: End-to-end browser testing.
Type: stdio
Command: npx @playwright/mcp@latest

Name: Sentry
Description: Error tracking and performance monitoring.
Type: streamableHttp
URL: https://mcp.sentry.dev/mcp

Name: DuckDB
Description: In-process SQL OLAP database for local analytics.
Type: stdio
Command: uvx mcp-server-motherduck --db-path :memory:
Environment Variables: motherduck_token = VARIABLE VALUE

Name: Vercel
Description: Manage projects and deployments on Vercel.
Type: streamableHttp
URL: https://mcp.vercel.com

Name: GitLab
Description: DevSecOps platform for code, CI/CD, and security.
Type: stdio
Command: npx mcp-remote https://your-gitlab-instance.com/api/v4/mcp

Name: Altlassian
Description: Project management and collaboration tools including Jira and Confluence.
Type: stdio
Command: npx mcp-remote https://mcp.atlassian.com/v1/sse

Name: PostHog
Description: Analytics, error tracking, and feature flags.
Type: stdio
Command: npx -y mcp-remote@latest https://mcp.posthog.com/sse --header Authorization:${POSTHOG_AUTH_HEADER}

Name: Stripe
Description: Payment processing APIs.
Type: stdio
Command: npx -y @stripe/mcp --tools=all

Name: PayPal
Description: Payment APIs.
Type: stdio
Command: npx -y mcp-remote https://mcp.paypal.com/sse

Name: dbt Labs
Description: dbt CLI, Semantic Layer, and Discovery API.
Type: stdio
Command: uvx dbt-mcp
Environment Variables: 
    DBT_MCP_HOST = cloud.getdbt.com
    MULTICELL_ACCOUNT_PREFIX = optional-account-prefix
    DBT_TOKEN = your-service-token
    DBT_PROD_ENV_ID = your-production-environment-id
    DBT_DEV_ENV_ID = your-development-environment-id
    DBT_USER_ID = your-user-id
    DBT_PROJECT_DIR = /path/to/your/dbt/project
    DBT_PATH = /path/to/your/dbt/executable
    DISABLE_DBT_CLI = false
    DISABLE_SEMANTIC_LAYER = false
    DISABLE_DISCOVERY = false
    DISABLE_REMOTE = false

Name: Browserbase
Description: Headless browser sessions for agents.
Type: stdio
Command: npx @browserbasehq/mcp
Environment Variables:
    BROWSERBASE_API_KEY = VARIABLE VALUE
    BROWSERBASE_PROJECT_ID = VARIABLE VALUE

Name: Netlify
Description: Build and deploy web projects.
Type: stdio
Command: npx mcp-remote npx -y @netlify/mcp

Name: Shopify
Description: Shopify app development tools.
Type: stdio
Command: npx -y @shopify/dev-mcp@latest

Name: Heroku
Description: Manage Heroku apps and resources.
Type: stdio
Command: npx -y @heroku/mcp-server

Name: Hugging Face
Description: Access the Hugging Face Hub and Gradio MCP Servers.
Type: streamableHttp
URL: https://hf.co/mcp

Name: Plaid
Description: Access financial account data.
Type: streamableHttp
URL: https://api.dashboard.plaid.com/mcp/sse

Name: Mercato Pago
Description: Access Mercado Pago docs.
Type: streamableHttp
URL: https://mcp.mercadopago.com/mcp

Name: Context7
Description: Up-to-date code documentation.
Type: streamableHttp
URL: https://mcp.context7.com/mcp

Name: InstantDB
Description: Query and manage InstantDB.
Type: streamableHttp
URL: https://mcp.instantdb.com/mcp

Name: TinyBird
Description: Real-time analytics APIs.
Type: stdio
Command: npx -y mcp-remote https://cloud.tinybird.co/mcp?token=TB_TOKEN

Name: Select Star
Description: Data catalog, lineage, and context.
Type: stdio
Command: npx -y mcp-remote@latest https://mcp.production.selectstar.com/mcp --header Authorization:${SELECT_STAR_TOKEN}
Environment Variables: SELECT_STAR_TOKEN = VARIABLE VALUE

Name: Pipedream
Description: Connect to APIs and workflows.
Type: streamableHttp
URL: https://mcp.pipedream.net/<uuid>/<app>

Name: MS Learn Docs
Description: Search Microsoft docs.
Type: streamableHttp
URL: https://learn.microsoft.com/api/mcp

Name: Railway
Description: Deploy apps, databases, and services.
Type: stdio
Command: npx -y @railway/mcp-server

