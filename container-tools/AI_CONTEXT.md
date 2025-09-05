# Universal Docker Entrypoint - AI Context

## Project Overview
Universal Docker Entrypoint is a cross-platform, modular Docker initialization system using Strategy Pattern. It provides secure user management, flexible execution modes, and comprehensive initialization workflows.

## Core Architecture

### Directory Structure
```
container-tools/
├── build/
│   └── setup-container-user.sh          # Build-time user setup
├── core/                                # Core libraries
│   ├── logger.sh                        # Unified logging system
│   ├── common.sh                        # Common utilities & mode management
│   ├── platform.sh                     # Cross-platform command wrappers
│   ├── permissions.sh                   # Advanced permissions management
│   ├── process.sh                       # Process management & script execution
│   └── executors.sh                     # Timeout executors
├── entrypoint/
│   ├── universal-entrypoint.sh          # Main orchestrator
│   ├── modules/                         # Initialization modules
│   │   ├── 00-environment.sh
│   │   ├── 10-permissions.sh
│   │   ├── 20-logging.sh
│   │   ├── 30-init-scripts.sh
│   │   ├── 40-dependencies.sh
│   │   └── 99-exec-command.sh
│   └── implementations/                 # Strategy Pattern implementations
│       ├── standard/                    # Real execution
│       └── dry_run/                     # Simulation mode
```


## Execution Modes & Error Policies

### Execution Modes (EXEC_MODE)
- **0 - STANDARD**: Full initialization + command execution
- **1 - SKIP_ALL**: Skip all initialization, execute command directly
- **2 - INIT_ONLY**: Only initialization, skip command execution
- **3 - DEBUG**: Debug mode with detailed logging
- **4 - DRY_RUN**: Show execution plan without actual execution

### Error Policies (EXEC_ERROR_POLICY)
- **0 - STRICT**: Any error stops execution
- **1 - SOFT**: Log error and continue
- **2 - CUSTOM**: Customizable error handling

## Required Environment Variables

### Core Variables
- `CONTAINER_TOOLS`: Path to container-tools (e.g., /opt/container-tools)
- `CONTAINER_NAME`: Container identifier
- `CONTAINER_USER`: Target application user
- `CONTAINER_UID`: Target user UID
- `CONTAINER_GID`: Target user GID
- `CONTAINER_TEMP`: Temporary directory path
- `CONTAINER_ENTRYPOINT_SCRIPTS`: Init scripts directory
- `CONTAINER_ENTRYPOINT_CONFIGS`: Config files directory
- `CONTAINER_ENTRYPOINT_DEPENDENCIES`: Dependency scripts directory

### Optional Variables
- `CONTAINER_GROUP`: Target group name (default: root)
- `DEPENDENCY_TIMEOUT`: Total timeout for dependencies in seconds (default: 300)
- `LOG_LEVEL`: Logging level (default: INFO)
- `LOG_DIR`: Log directory (default: /var/log/$CONTAINER_NAME)

## Key Functions Library

### Logging (logger.sh)
- `log info "message"` - Info level logging
- `log success "message"` - Success logging
- `log warning "message"` - Warning logging
- `log error "message"` - Error logging
- `log debug "message"` - Debug logging
- `log header "title"` - Section headers
- `log step "number" "description"` - Step logging

### Platform Operations (platform.sh)
- `platform user exists "username"` - Check if user exists
- `platform group exists "groupname"` - Check if group exists
- `platform_switch_user "user" "command"` - Switch user and exec command
- `get_user_home "username"` - Get user home directory
- `get_user_uid "username"` - Get user UID
- `get_user_gid "username"` - Get user GID
- `platform_chmod_recursive "perms" "path" "type"` - Recursive chmod

### Common Utilities (common.sh)
- `detect_os()` - Detect operating system
- `detect_os_family()` - Detect OS family (debian/rhel/alpine)
- `cmn command check "command"` - Check if command exists
- `cmn env check-vars var1 var2 ...` - Validate required variables
- `cmn modes get-exec()` - Get current execution mode as string
- `cmn modes get-err()` - Get current error policy as string
- `should_execute_in_mode "operation" "mode"` - Check if operation should run
- `safe_mkdir "path" "owner" "perms"` - Create directory safely
- `prepare_user_environment "user" "create_home"` - Prepare user env

### Permissions Management (permissions.sh)
- `setup_permissions --path="..." --owner="..." --perms="..." --flags="..."` - Main permissions function
- Flags: create/required/optional, strict/soft/silent, file-only/dir-only/auto, recursive/non-recursive, executable
- `setup_log_permissions "path" "owner"` - Quick log directory setup
- `setup_app_permissions "path" "owner"` - Quick app directory setup
- `setup_script_permissions "path" "owner"` - Quick script permissions

### Process Management (process.sh)
- `execute_script_safely "script" "error_policy" "timeout" "description"` - Safe script execution
- `execute_scripts_in_directory "dir" "error_policy" "timeout" "pattern"` - Execute all scripts in directory
- `exec_final_command "user" "command"` - Final command execution with user switch

### Timeout Executors (executors.sh)
- `execute_command_with_timeout --timeout=N --description="..." --command cmd args` - Command with timeout
- `execute_function_with_timeout --timeout=N --description="..." --function func_name args` - Function with timeout

## Module Execution Flow

### Initialization Sequence
1. **00-environment.sh**: OS detection, command validation, user validation, directory structure
2. **10-permissions.sh**: Set up permissions for temp, logs, scripts, configs, dependencies, container-tools
3. **20-logging.sh**: Configure logging environment variables and verify log directory
4. **30-init-scripts.sh**: Execute user-provided initialization scripts from CONTAINER_ENTRYPOINT_SCRIPTS
5. **40-dependencies.sh**: Wait for dependencies using scripts from CONTAINER_ENTRYPOINT_DEPENDENCIES with total timeout
6. **99-exec-command.sh**: Switch to target user and execute final command

### Strategy Pattern Implementation
Each module loads appropriate implementation:
- **standard/**: Real execution of operations
- **dry_run/**: Simulation showing what would be executed

Implementation loading: `load_module_implementation "module-name"`

## Security Model

### Permission Structure
- **Container temp**: 700/600 for user data
- **Log directories**: 700/600 for application logs
- **Init scripts**: 700/700 + executable for user scripts
- **Config files**: 700/600 for configuration data
- **Container tools**: 750/750 + executable for system tools

### User Management
- Root entrypoint → Application user execution
- Proper UID/GID validation and mapping
- Cross-platform user switching
- Home directory creation and ownership

## Common Usage Patterns

### Dockerfile Setup

```dockerfile
ENV CONTAINER_TOOLS=/opt/container-tools \
    CONTAINER_USER=appuser \
    CONTAINER_UID=1000 \
    CONTAINER_GID=1000 \
    CONTAINER_NAME=my-app \
    CONTAINER_TEMP=/tmp/my-app

COPY .. ${CONTAINER_TOOLS}/
RUN ${CONTAINER_TOOLS}/build/setup-container-user.sh ${CONTAINER_USER} ${CONTAINER_UID} ${CONTAINER_GROUP} ${CONTAINER_GID}

ENTRYPOINT ["bash", "/opt/container-tools/entrypoint/universal-entrypoint.sh"]
```


### Runtime Examples
- Standard: `docker run my-app`
- DRY_RUN: `docker run -e EXEC_MODE=4 my-app`
- Init only: `docker run -e EXEC_MODE=2 my-app`
- Skip all: `docker run -e EXEC_MODE=1 my-app`

### User Scripts
- Place .sh files in CONTAINER_ENTRYPOINT_SCRIPTS for initialization
- Place .sh files in CONTAINER_ENTRYPOINT_DEPENDENCIES for dependency waiting
- Scripts execute in lexicographic order
- All scripts respect error policy settings

## Troubleshooting Patterns

### Common Issues
- Missing bash: Install bash in container
- CONTAINER_TOOLS not set: Set environment variable
- User doesn't exist: Run setup-container-user.sh during build
- Permission denied: Check ownership and executable bits
- Timeout issues: Adjust DEPENDENCY_TIMEOUT

### Debug Techniques
- Use EXEC_MODE=4 (DRY_RUN) to see execution plan
- Use EXEC_MODE=3 (DEBUG) for detailed logs
- Check LOG_LEVEL=DEBUG for maximum verbosity
- Use EXEC_MODE=2 (INIT_ONLY) to test initialization without app

This context provides complete understanding of the Universal Docker Entrypoint architecture and all available functionality.