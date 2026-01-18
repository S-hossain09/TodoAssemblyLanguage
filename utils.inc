; Writes an unsigned integer to a file descriptor
; rdi = file descriptor, rsi = integer to write
write_uint:
    test rsi, rsi
    jz .base_zero

    mov rcx, 10     ; Divisor for extracting decimal digits
    mov rax, rsi    ; Number to convert
    mov r10, 0      ; Digit counter
.next_digit:
    ; Extract digits by repeatedly dividing by 10
    test rax, rax
    jz .done
    mov rdx, 0
    div rcx         ; rax = quotient, rdx = remainder (digit)
    add rdx, '0'    ; Convert digit to ASCII
    dec rsp         ; Push digit onto stack
    mov byte [rsp], dl
    inc r10         ; Count this digit
    jmp .next_digit
.done:
    ; Write all accumulated digits from stack
    write rdi, rsp, r10
    add rsp, r10    ; Clean up stack
    ret
.base_zero:
    ; Special case: write '0' for zero value
    dec rsp
    mov byte [rsp], '0'
    write rdi, rsp, 1
    inc rsp
    ret

; Writes a null-terminated string to a file descriptor
; rdi = file descriptor, rsi = pointer to string
write_cstr:
    push rsi
    push rdi
    mov rdi, rsi
    call strlen     ; Get string length

    mov rdx, rax    ; Length for write syscall
    mov rax, SYS_write
    pop rdi         ; Restore file descriptor
    pop rsi         ; Restore string pointer
    syscall
    ret

; Calculates the length of a null-terminated string
; rdi = pointer to string
; Returns: rax = length (excluding null terminator)
strlen:
    push rdi
    xor rax, rax
.next_char:
    mov al, byte [rdi]
    cmp rax, 0      ; Check for null terminator
    je .done

    inc rdi
    jmp .next_char
.done:
    pop rsi
    sub rdi, rsi    ; Calculate length by pointer subtraction
    mov rax, rdi
    ret

; Parses a string of ASCII digits into an unsigned integer
; rdi = pointer to string, rsi = length
; Returns: rax = parsed integer
parse_uint:
    xor rax, rax    ; Accumulator for result
    xor rbx, rbx    ; Current digit
    mov rcx, 10     ; Multiplier for decimal
.next_digit:
    cmp rsi, 0
    jle .done

    mov bl, byte [rdi]
    cmp rbx, '0'    ; Validate digit is in range '0'-'9'
    jl .done
    cmp rbx, '9'
    jg .done
    sub rbx, '0'    ; Convert ASCII to numeric value

    mul rcx         ; Shift existing digits left (multiply by 10)
    add rax, rbx    ; Add new digit

    inc rdi
    dec rsi
    jmp .next_digit
.done:
    ret

; Copies memory from source to destination
; rdi = destination, rsi = source, rdx = byte count
memcpy:
.next_byte:
   cmp rdx, 0
   jle .done

   mov al, byte [rsi]
   mov byte [rdi], al

   inc rdi
   inc rsi
   dec rdx

   jmp .next_byte
.done:
   ret

; Searches for a character in a buffer
; rdi = pointer to buffer, rsi = length, dl = character to find
; Returns: rax = pointer to character if found, 0 if not found
find_char:
   cmp rsi, 0
   jle .not_found

   mov al, byte [rdi]
   cmp dl, al
   je .found

   inc rdi
   dec rsi
   jmp find_char

.not_found:
   xor rax, rax
   ret
.found:
   mov rax, rdi
   ret

; Checks if a string starts with a given prefix
; rdi = haystack pointer, rsi = haystack length
; rdx = needle pointer, r10 = needle length
; Returns: rax = 1 if starts with prefix, 0 otherwise
starts_with:
    xor rax, rax
    xor rbx, rbx
.next_char:
    ; Stop if we've exhausted either string
    cmp rsi, 0
    jle .done
    cmp r10,0
    jle .done

    ; Compare current characters
    mov al, byte [rdi]
    mov bl, byte [rdx]
    cmp rax, rbx
    jne .done       ; Mismatch - return 0

    dec rsi
    inc rdi
    dec r10
    inc rdx
    jmp .next_char

.done:
    ; Success if we've consumed entire needle
    cmp r10, 0
    je .yes
.no:
    mov rax, 0
    ret
.yes:
    mov rax, 1
    ret