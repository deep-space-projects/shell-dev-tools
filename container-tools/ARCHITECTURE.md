# Universal Docker Entrypoint - Technical Architecture

## Overview

Universal Docker Entrypoint is a production-ready, cross-platform Docker initialization system built with modular architecture and Strategy Pattern. It provides secure user management, flexible execution modes, comprehensive initialization workflows, and robust error handling for enterprise containerized applications.

## Core Design Principles

### 1. Modular Architecture
- **Separation of Concerns**: Each module handles a specific initialization aspect
- **Strategy Pattern**: Multiple implementations (standard/dry_run) for the same interface
- **Dependency Injection**: Modules load appropriate implementations based on execution mode

### 2. Cross-Platform Compatibility
- **OS Family Support**: Alpine, Debian/Ubuntu, RHEL/CentOS/Rocky/Alma
- **Command Abstraction**: Platform-specific command wrappers with fallbacks
- **Minimal System Support**: Works with BusyBox and full distributions

### 3. Security First
- **Principle of Least Privilege**: Restrictive permissions by default
- **User Isolation**: Clean separation between root initialization and app execution
- **Permission Validation**: Comprehensive ownership and access control verification

## Technical Architecture

### System Components

#### Core Libraries (/core/)
```
logger.sh       - Unified logging with levels, colors, timestamps
common.sh       - OS detection, utilities, mode management
platform.sh     - Cross-platform command wrappers
permissions.sh  - Advanced permission management with flag system
process.sh      - Process management, script execution, user switching
executors.sh    - Timeout handling, graceful process termination
```


#### Initialization Modules (/entrypoint/modules/)
```
00-environment.sh    - OS detection, command validation, user verification
10-permissions.sh    - Directory creation, ownership, access control
20-logging.sh        - Log environment setup, directory validation
30-init-scripts.sh   - User initialization scripts execution
40-dependencies.sh   - Dependency waiting with timeout management
99-exec-command.sh   - Final command execution with user switching
```


#### Strategy Implementations (/entrypoint/modules/implementations/)
- **standard/**: Real execution implementations
- **dry_run/**: Simulation implementations for testing and validation

### Data Flow Architecture

#### 1. Bootstrap Phase
```
universal-entrypoint.sh
├── Bash requirement check
├── CONTAINER_TOOLS validation
├── Core libraries loading
└── Environment validation
```


#### 2. Module Execution Phase
```
For each module (00 → 10 → 20 → 30 → 40 → 99):
├── Load appropriate implementation (standard/dry_run)
├── Execute module with error policy enforcement
├── Handle success/failure based on execution mode
└── Continue or abort based on error policy
```


#### 3. Command Execution Phase
```
99-exec-command.sh
├── Pre-execution validation
├── User environment preparation
├── User switching (root → app user)
└── Final command execution (exec)
```


### Permission Security Model

#### Directory Structure and Permissions
```
/var/log/CONTAINER_NAME/     700/600  appuser:appgroup  # Application logs
/tmp/CONTAINER_NAME/         700/600  appuser:appgroup  # Temporary files
  ├── init/                  700/700  appuser:appgroup  # Init scripts (executable)
  ├── config/                700/600  appuser:appgroup  # Configuration files
  └── dependencies/          700/700  appuser:appgroup  # Dependency scripts
/opt/container-tools/        750/750  appuser:appgroup  # System tools (group access)
```


#### Permission Flag System
Advanced permission management with composable flags:
- **Existence**: create/required/optional
- **Error Handling**: strict/soft/silent
- **Target Type**: file-only/dir-only/auto
- **Recursion**: recursive/non-recursive
- **Symlinks**: follow-symlinks/no-follow-symlinks
- **Actions**: executable, files-only, dirs-only

### Execution Mode System

#### Mode Decision Matrix
| Mode | Init | Dependencies | Exec | Use Case |
|------|------|-------------|------|----------|
| STANDARD (0) | ✓ | ✓ | ✓ | Production deployment |
| SKIP_ALL (1) | ✗ | ✗ | ✓ | Emergency bypass |
| INIT_ONLY (2) | ✓ | ✓ | ✗ | Initialization testing |
| DEBUG (3) | ✓ | ✓ | ✓ | Troubleshooting |
| DRY_RUN (4) | ✓ | ✓ | ✓ | Execution planning |

#### Error Policy Implementation
```shell script
handle_operation_error_quite() {
    case "$EXEC_ERROR_POLICY" in
        0) # STRICT - Stop execution
        1) # SOFT - Log warning, continue
        2) # CUSTOM - Return error code for custom handling
    esac
}
```


## API Reference

### Core Function Signatures

#### Logging System
```shell script
log info "message"                          # Standard information logging
log success "message"                       # Success operation logging  
log warning "message"                       # Warning condition logging
log error "message"                         # Error condition logging
log debug "message"                         # Debug information logging
log header "title"                          # Section header with separators
log step "number" "description"             # Numbered step logging
log_component "component" "level" "message" # Component-prefixed logging
```


#### Platform Operations
```shell script
platform user exists "username"                    # → 0=exists, 1=not exists
platform group exists "groupname"                  # → 0=exists, 1=not exists
platform_switch_user "user" "command"              # exec as user (no return)
platform_chmod_recursive "perms" "path" "type"     # type: all|files|dirs
get_user_home "username"                           # → home directory path
get_user_uid "username"                            # → numeric UID
get_user_gid "username"                            # → numeric GID
platform_user_in_group "user" "group"             # → 0=member, 1=not member
```


#### Permission Management
```shell script
setup_permissions \
    --path="/path/to/target" \
    --owner="user:group" \
    --perms="755" \
    --dir-perms="755" \
    --file-perms="644" \
    --flags="create,strict,recursive,executable"

# Convenience functions
setup_log_permissions "path" "owner"       # 755/644 with create,strict
setup_app_permissions "path" "owner"       # 750/640 with required,strict  
setup_script_permissions "path" "owner"    # 755/755 with executable
```


#### Process Management
```shell script
execute_script_safely "script" "error_policy" "timeout" "description"
execute_scripts_in_directory "dir" "error_policy" "timeout" "pattern"
exec_final_command "user" "command_string"

# Timeout executors
execute_command_with_timeout \
    --timeout=300 \
    --description="Database migration" \
    --command python migrate.py

execute_function_with_timeout \
    --timeout=60 \
    --description="Health check" \
    --function check_service_health param1 param2
```


### Environment Variable Schema

#### Required Variables
```shell script
CONTAINER_TOOLS="/opt/container-tools"                    # System tools path
CONTAINER_NAME="my-application"                           # Container identifier
CONTAINER_USER="appuser"                                  # Target app user
CONTAINER_UID="1000"                                      # Target app UID
CONTAINER_GID="1000"                                      # Target app GID  
CONTAINER_TEMP="/tmp/my-application"                      # Temp directory
CONTAINER_ENTRYPOINT_SCRIPTS="/tmp/my-application/init"   # Init scripts
CONTAINER_ENTRYPOINT_CONFIGS="/tmp/my-application/config" # Config files
CONTAINER_ENTRYPOINT_DEPENDENCIES="/tmp/my-application/dependencies" # Deps
```


#### Optional Variables
```shell script
CONTAINER_GROUP="appgroup"          # Target group name (default: root)
EXEC_MODE="0"                       # Execution mode (default: 0=STANDARD)
EXEC_ERROR_POLICY="0"               # Error policy (default: 0=STRICT)
DEPENDENCY_TIMEOUT="300"            # Dep timeout seconds (default: 300)
LOG_LEVEL="INFO"                    # Log level (default: INFO)
LOG_COLORS="true"                   # Colored output (default: true)
LOG_TIMESTAMPS="true"               # Timestamp logging (default: true)
```


## Integration Patterns

### Dockerfile Integration
```dockerfile
FROM alpine:3.19

# Install bash (required)
RUN apk add --no-cache bash

# Set up environment
ENV CONTAINER_TOOLS=/opt/container-tools \
    CONTAINER_USER=myapp \
    CONTAINER_UID=1000 \
    CONTAINER_GID=1000 \
    CONTAINER_GROUP=myapp \
    CONTAINER_NAME=my-application \
    CONTAINER_TEMP=/tmp/my-application \
    CONTAINER_ENTRYPOINT_SCRIPTS=/tmp/my-application/init \
    CONTAINER_ENTRYPOINT_CONFIGS=/tmp/my-application/config \
    CONTAINER_ENTRYPOINT_DEPENDENCIES=/tmp/my-application/dependencies

# Copy container-tools
COPY container-tools/ ${CONTAINER_TOOLS}/

# Copy user scripts (optional)
COPY init-scripts/ ${CONTAINER_ENTRYPOINT_SCRIPTS}/
COPY dependency-scripts/ ${CONTAINER_ENTRYPOINT_DEPENDENCIES}/

# Set up user and permissions
RUN chmod +x ${CONTAINER_TOOLS}/build/setup-container-user.sh && \
    ${CONTAINER_TOOLS}/build/setup-container-user.sh \
        ${CONTAINER_USER} ${CONTAINER_UID} ${CONTAINER_GROUP} ${CONTAINER_GID}

# Set entrypoint
ENTRYPOINT ["bash", "/opt/container-tools/entrypoint/universal-entrypoint.sh"]
CMD ["my-application", "--config", "/app/config.yml"]
```


### User Script Examples

#### Init Script (/tmp/app/init/01-database-setup.sh)
```shell script
#!/bin/bash
set -euo pipefail

echo "Setting up database connection..."

# Available functions from core libraries
log info "Configuring database settings"

# Check database connectivity
if ! nc -z postgres 5432; then
    log error "Database not accessible"
    exit 1
fi

# Run migrations
python manage.py migrate
log success "Database setup completed"
```


#### Dependency Script (/tmp/app/dependencies/01-wait-redis.sh)
```shell script
#!/bin/bash
set -euo pipefail

echo "Waiting for Redis..."

# This runs under DEPENDENCY_TIMEOUT
while ! nc -z redis 6379; do
    echo "Redis not ready, waiting..."
    sleep 2
done

echo "Redis is ready!"
```


### Runtime Configuration Examples

#### Production Deployment
```shell script
docker run \
    -e EXEC_MODE=0 \
    -e EXEC_ERROR_POLICY=0 \
    -e DEPENDENCY_TIMEOUT=300 \
    my-application
```


#### Development with Debug
```shell script
docker run \
    -e EXEC_MODE=3 \
    -e LOG_LEVEL=DEBUG \
    -e EXEC_ERROR_POLICY=1 \
    my-application
```


#### Testing Initialization
```shell script
# Test init only (no app start)
docker run -e EXEC_MODE=2 my-application

# Dry run (show execution plan)
docker run -e EXEC_MODE=4 my-application
```


## Error Handling & Troubleshooting

### Common Error Patterns

#### Missing Dependencies
```
❌ ERROR: bash is required but not found
→ Solution: RUN apk add --no-cache bash

❌ ERROR: CONTAINER_TOOLS environment variable is not set  
→ Solution: ENV CONTAINER_TOOLS=/opt/container-tools

❌ ERROR: Target user does not exist: appuser
→ Solution: Run setup-container-user.sh during build
```


#### Permission Issues
```
❌ ERROR: Failed to set owner 'appuser:appgroup' on '/var/log/myapp'
→ Check: Container running as root for initial setup
→ Check: User and group created correctly

❌ WARNING: Not running as root (UID: 1000) - some permission operations may fail
→ Expected: Normal for final command execution phase
```


#### Timeout Problems
```
❌ ERROR: Command 'Database migration' terminated due to timeout (300s)
→ Solution: Increase DEPENDENCY_TIMEOUT
→ Debug: Use EXEC_MODE=4 to validate script logic

❌ ERROR: Dependencies scripts execution failed
→ Debug: Check individual dependency scripts
→ Solution: Use EXEC_ERROR_POLICY=1 for non-critical deps
```


### Debug Techniques

#### Execution Planning
```shell script
# See complete execution plan
docker run -e EXEC_MODE=4 my-app

# Output example:
[DRY RUN] Would detect operating system using cmn os detect()
[DRY RUN] Would check required commands: id, whoami, chmod, chown  
[DRY RUN] Would create directory: /var/log/my-app
[DRY RUN] Found 2 init scripts: 01-db-setup.sh, 02-cache-warm.sh
[DRY RUN] Would execute final command: my-application --config /app/config.yml
```


#### Detailed Logging
```shell script
# Maximum verbosity
docker run \
    -e EXEC_MODE=3 \
    -e LOG_LEVEL=DEBUG \
    -e LOG_TIMESTAMPS=true \
    my-app
```


#### Selective Testing
```shell script
# Test only initialization
docker run -e EXEC_MODE=2 my-app

# Skip initialization for emergency
docker run -e EXEC_MODE=1 my-app
```


## Performance Considerations

### Optimization Strategies
- **Parallel Dependencies**: Use separate containers for independent services
- **Cache User Scripts**: Pre-validate scripts during build phase
- **Minimize Permission Changes**: Group related operations
- **Timeout Tuning**: Set appropriate DEPENDENCY_TIMEOUT for environment

### Resource Usage
- **Memory**: Minimal overhead (~1-2MB for bash processes)
- **CPU**: Low impact, mainly I/O bound operations
- **Disk**: Temporary files cleaned up automatically
- **Network**: Only for dependency checks (user-defined)

## Extension Points

### Custom Implementations
Add new execution modes by creating implementation files:
```shell script
entrypoint/modules/implementations/custom/
├── environment-impl.sh
├── permissions-impl.sh
└── ...
```


### Module Development
Create new modules following the pattern:
```shell script
# 05-custom-module.sh
load_module_implementation "custom-module"
module() {
    log header "CUSTOM MODULE"
    # Implementation calls
}
```


### Integration Hooks
- **Pre-hooks**: Add scripts to CONTAINER_ENTRYPOINT_SCRIPTS
- **Post-hooks**: Modify final command or use wrapper scripts
- **Monitoring**: Parse structured logs for operational metrics

This architecture documentation provides complete technical understanding for development, deployment, and maintenance of Universal Docker Entrypoint systems.