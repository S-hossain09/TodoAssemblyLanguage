; ============================================================================
; Linux System Call Numbers (x86-64)
; ============================================================================

SYS_read equ 0
SYS_write equ 1
SYS_open equ 2
SYS_close equ 3
SYS_fstat64 equ 5
SYS_socket equ 41
SYS_accept equ 43
SYS_bind equ 49
SYS_listen equ 50
SYS_setsockopt equ 54
SYS_exit equ 60

; ============================================================================
; File Operation Flags
; ============================================================================

O_RDONLY = 0        ; Open for reading only
O_WRONLY = 1        ; Open for writing only
O_CREAT = 64        ; Create file if it doesn't exist
O_TRUNC = 512       ; Truncate file to zero length

; ============================================================================
; Socket Constants
; ============================================================================

AF_INET equ 2           ; IPv4 Internet protocols
SOCK_STREAM equ 1       ; TCP socket type
INADDR_ANY equ 0        ; Bind to all available interfaces

; Socket options
SOL_SOCKET = 1          ; Socket-level options
SO_REUSEADDR = 2        ; Allow reuse of local addresses
SO_REUSEPORT = 15       ; Allow reuse of local ports

SOL_TCP = 6             ; TCP-level options
TCP_NODELAY = 1         ; Disable Nagle's algorithm

; ============================================================================
; Standard File Descriptors
; ============================================================================

STDOUT equ 1            ; Standard output
STDERR equ 2            ; Standard error

; ============================================================================
; Character Constants
; ============================================================================

NEW_LINE equ 10         ; Line feed character '\n'
CARRIAGE_RETURN equ 13  ; Carriage return '\r'
END_OF_STRING equ 0     ; Null terminator

; ============================================================================
; Exit Codes
; ============================================================================

EXIT_SUCCESS equ 0
EXIT_FAILURE equ 1

; ============================================================================
; stat64 Structure Offsets
; ============================================================================

sizeof_stat64 = 144     ; Total size of stat64 structure
stat64.st_size = 48     ; Offset to file size field

; ============================================================================
; Function Call Macros
; Simplify passing arguments in System V AMD64 ABI registers
; ============================================================================

macro funcall2 func, a, b
{
    mov rdi, a          ; First argument
    mov rsi, b          ; Second argument
    call func
}

macro funcall3 func, a, b, c
{
    mov rdi, a          ; First argument
    mov rsi, b          ; Second argument
    mov rdx, c          ; Third argument
    call func
}

macro funcall4 func, a, b, c, d
{
    mov rdi, a          ; First argument
    mov rsi, b          ; Second argument
    mov rdx, c          ; Third argument
    mov r10, d          ; Fourth argument
    call func
}

; ============================================================================
; System Call Macros
; Wrap common syscalls with automatic register setup
; ============================================================================

macro syscallArg1 number, a
{
    mov rax, number     ; Syscall number
    mov rdi, a          ; First argument
    syscall
}

macro syscallArg2 number, a, b
{
    mov rax, number     ; Syscall number
    mov rdi, a          ; First argument
    mov rsi, b          ; Second argument
    syscall
}

macro syscallArg3 number, a, b, c
{
    mov rax, number     ; Syscall number
    mov rdi, a          ; First argument
    mov rsi, b          ; Second argument
    mov rdx, c          ; Third argument
    syscall
}

macro syscallArg5 number, a, b, c, d, e
{
    mov rax, number     ; Syscall number
    mov rdi, a          ; First argument
    mov rsi, b          ; Second argument
    mov rdx, c          ; Third argument
    mov r10, d          ; Fourth argument
    mov r8,  e          ; Fifth argument
    syscall
}

; ============================================================================
; High-Level System Call Wrappers
; ============================================================================

; Write data to a file descriptor
macro write fd, buf, count
{
    syscallArg3 SYS_write, fd, buf, count
}

; Read data from a file descriptor
macro read fd, buf, count
{
    syscallArg3 SYS_read, fd, buf, count
}

; Close a file descriptor
macro close fd
{
    syscallArg1 SYS_close, fd
}

; Create a socket
macro socket domain, type, protocol
{
    syscallArg3 SYS_socket, domain, type, protocol
}

; Bind a socket to an address
macro bind sockfd, addr, addrlen
{
    syscallArg3 SYS_bind, sockfd, addr, addrlen
}

; Listen for connections on a socket
macro listen sockfd, backlog
{
    syscallArg2 SYS_listen, sockfd, backlog
}

; Accept a connection on a socket
macro accept sockfd, addr, addrlen
{
    syscallArg3 SYS_accept, sockfd, addr, addrlen
}

; Terminate the program
macro exit code
{
    syscallArg1 SYS_exit, code
}

; Open a file
macro open filename, flags, mode
{
    syscallArg3 SYS_open, filename, flags, mode
}

; Set socket options
macro setsockopt sockfd, level, optname, optval, optlen
{
    syscallArg5 SYS_setsockopt, sockfd, level, optname, optval, optlen
}

; Get file status
macro fstat64 fd, statbuf
{
    syscallArg2 SYS_fstat64, fd, statbuf
}

; ============================================================================
; Socket Address Structure (IPv4)
; ============================================================================

struc servaddr_in
{
    .sin_family dw 0    ; Address family (AF_INET)
    .sin_port   dw 0    ; Port number (network byte order)
    .sin_addr   dd 0    ; IPv4 address (network byte order)
    .sin_zero   dq 0    ; Padding to match sockaddr size
}