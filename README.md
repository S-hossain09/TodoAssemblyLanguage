# TodoAssemblyLanguage

# Resources Link:
1. Linux manual page: https://man7.org/linux/man-pages/man2/open.2.html
2. https://blog.rchapman.org/posts/Linux_System_Call_Table_for_x86_64/

# Assembly Todo Web Server - Technical Overview

## What This Is

A minimal HTTP web server written entirely in x86-64 assembly language that manages a todo list. It runs directly on Linux without any external libraries or dependencies - just raw system calls.

## Architecture Overview

### Three Main Components

1. **linux.inc** - System call interface and macros
2. **utils.inc** - Utility functions (string operations, parsing)
3. **todo.asm** - Web server logic and HTTP handling

## How It Works

### 1. Server Startup

```
Load todos from disk (todo.db file)
  ↓
Create TCP socket on port 14619
  ↓
Configure socket options (SO_REUSEADDR, SO_REUSEPORT)
  ↓
Bind to all network interfaces (0.0.0.0)
  ↓
Start listening for connections
```

### 2. Request Processing Loop

The server runs an infinite loop:

```
Accept incoming connection
  ↓
Read HTTP request (up to 128KB)
  ↓
Parse HTTP method (GET or POST)
  ↓
Match route and execute handler
  ↓
Send HTTP response
  ↓
Close connection
  ↓
Return to accept next connection
```

### 3. Data Storage Format

**In-Memory Structure:**
- Array of 256 todo items
- Each todo is exactly 256 bytes:
  - Byte 0: Length of todo text (0-255)
  - Bytes 1-255: Todo text content

**On-Disk Format (todo.db):**
- Binary file storing the exact memory layout
- No header, no metadata - just raw todo blocks
- File size must be divisible by 256 bytes

### 4. HTTP Routes

| Method | Route | Action |
|--------|-------|--------|
| GET | / | Display todo list page |
| POST | / | Add new todo (form data: `todo=...`) |
| POST | / | Delete todo (form data: `delete=N`) |
| POST | /shutdown | Shutdown server |

### 5. HTTP Request Parsing

**Parse Method:**
```
Check if starts with "GET " → handle GET
Check if starts with "POST " → handle POST
Otherwise → 405 Method Not Allowed
```

**Parse Route:**
```
Check if starts with "/ " → index page
Check if starts with "/shutdown " → shutdown
Otherwise → 404 Not Found
```

**Parse POST Body:**
```
Skip all HTTP headers (until \r\n\r\n)
  ↓
Check form data prefix:
  - "todo=" → add new todo
  - "delete=" → delete todo by index
```

## Key Operations Explained

### Adding a Todo

1. Extract todo text from POST body (after "todo=" prefix)
2. Truncate to 255 characters if longer
3. Find next free slot in todo array
4. Write length byte + text content
5. Update `todo_end_offset` (tracks used space)
6. Write entire array to disk

### Deleting a Todo

1. Parse todo index from POST body (after "delete=" prefix)
2. Calculate byte offset: `index × 256`
3. Copy all todos after deleted one to fill the gap (using `memcpy`)
4. Decrease `todo_end_offset` by 256
5. Write updated array to disk

### Rendering HTML

1. Send HTTP 200 response headers
2. Send HTML header (`<h1>To-Do</h1><ul>`)
3. For each todo:
   - Generate delete button with todo index
   - Write todo text (read length from first byte)
4. Send HTML footer (includes add form + shutdown button)

## Utility Functions Deep Dive

### `write_uint` - Convert Integer to ASCII

Converts a number to decimal string by repeatedly dividing by 10:
```
123 → Extract digits in reverse: 3, 2, 1
    → Push to stack: '3', '2', '1'
    → Write from stack: "123"
```

### `parse_uint` - Convert ASCII to Integer

Builds number by processing each digit:
```
"456" → Start with 0
      → See '4': 0×10 + 4 = 4
      → See '5': 4×10 + 5 = 45
      → See '6': 45×10 + 6 = 456
```

### `starts_with` - String Prefix Matching

Compares strings byte-by-byte until either:
- All prefix bytes match → return 1
- Mismatch found → return 0
- Either string exhausted → return 0

### `memcpy` - Memory Copy

Simple byte-by-byte copy loop:
```
while (count > 0) {
    *dest = *src;
    dest++;
    src++;
    count--;
}
```

## System Call Interface (linux.inc)

### What Are System Calls?

Direct requests to the Linux kernel for privileged operations. The kernel provides services that userspace programs cannot do themselves:

- File I/O (`read`, `write`, `open`, `close`)
- Network operations (`socket`, `bind`, `listen`, `accept`)
- Process management (`exit`)

### How System Calls Work

1. Load syscall number into `rax`
2. Load arguments into specific registers (`rdi`, `rsi`, `rdx`, `r10`, `r8`)
3. Execute `syscall` instruction
4. Kernel returns result in `rax` (usually file descriptor or status code)

### Macros Simplify Usage

Instead of manually setting up registers:
```assembly
mov rax, 1        ; SYS_write
mov rdi, 1        ; STDOUT
mov rsi, message
mov rdx, 13
syscall
```

Use the macro:
```assembly
write STDOUT, message, 13
```

## Error Handling

The server uses a simple error strategy:

**Fatal Errors** (exit immediately):
- Socket creation fails
- Bind fails
- Listen fails

**Request Errors** (send HTTP error, continue):
- 400 Bad Request - Invalid POST data
- 404 Not Found - Unknown route
- 405 Method Not Allowed - Unknown HTTP method

## Performance Characteristics

**Advantages:**
- Zero dependencies - just Linux kernel
- Minimal memory footprint
- Direct system calls (no library overhead)
- Single-threaded simplicity

**Limitations:**
- Handles one connection at a time (blocking)
- No concurrency (can't handle multiple users simultaneously)
- Fixed 256-todo capacity
- No URL encoding/decoding
- No HTTPS support

## Memory Layout

```
[Code Section]
  - main loop
  - request handlers
  - utility functions

[Data Section]
  - HTTP response templates
  - Socket structures
  - Request buffer (128KB)
  - Todo array (256 × 256 bytes = 64KB)
  - File stat buffer
```

## Why Assembly?

This project demonstrates:
- **Low-level understanding** - How servers work without frameworks
- **System programming** - Direct kernel interaction
- **Performance optimization** - Every instruction counts
- **Minimalism** - Working with absolute essentials

It's educational rather than practical - real web servers use higher-level languages with libraries for HTTP parsing, concurrency, security, etc.

## How to Use

1. **Compile:** Assemble with FASM or similar
2. **Run:** Execute the binary
3. **Access:** Open browser to `http://localhost:6969`
4. **Add todos:** Type in the input field and click '+'
5. **Delete todos:** Click 'x' button next to any todo
6. **Shutdown:** Click 'shutdown' button

The server creates/updates `todo.db` file in the current directory to persist todos across restarts.