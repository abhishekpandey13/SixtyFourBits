;*********************************************************
; Ball demo
;
;  Written in Assembly x64
;
;  By David Antler  09/12/2017
;
;*********************************************************

;*********************************************************
; Assembly Options
;*********************************************************


;*********************************************************
; Included Files
;*********************************************************
include ksamd64.inc
include demovariables.inc
include master.inc

;*********************************************************
; External WIN32/C Functions
;*********************************************************
extern LocalAlloc:proc
extern LocalFree:proc
extern time:proc
extern srand:proc
extern rand:proc

;*********************************************************
; Structures
;*********************************************************
PARAMFRAME struct
    Param1         dq ?
    Param2         dq ?
    Param3         dq ?
    Param4         dq ?
PARAMFRAME ends

BALL_INFO struct
    X              dq ?
    Y              dq ?
    Radius         dq ?
    Color          dq ?
    Bounciness     dq ?
    Z              dq ?
    VelocityX      dq ?
    VelocityY      dq ?
BALL_INFO ends

SAVEREGSFRAME struct
    SaveRdi        dq ?
    SaveRsi        dq ?
    SaveRbx        dq ?
    SaveR10        dq ?
    SaveR11        dq ?
    SaveR12        dq ?
    SaveR13        dq ?
SAVEREGSFRAME ends

TEMPLATE_FUNCTION_STRUCT struct
   ParameterFrame PARAMFRAME      <?>
   SaveFrame      SAVEREGSFRAME   <?>
TEMPLATE_FUNCTION_STRUCT ends

;*********************************************************
; Public Declarations
;*********************************************************
public Ball_Init
public Ball_Demo
public Ball_Free

MAX_FRAMES     EQU <180000>
UPDATE_DIVISOR EQU <100>
GRAVITY        EQU <1>
GRAV_DIVISOR   EQU <1>
NUM_BALLS      EQU <6>
MAX_BOUNCINESS EQU <70>

;*********************************************************
; Data Segment
;*********************************************************

.CONST
   BackgroundColor dd 00FFFFFFh;

.DATA
                 ;   x,    y, radius,      color, bounce,    z,  VelocityX,  VelocityY 
   BallArray  dq    70,   20,     20,   0BB22DDh,     50,    1,          0,        -4 ;
              dq   340,  140,     70,   01122DDh,     40,    2,          0,        -1 ;
              dq   540,  160,     10,   0BB2211h,     50,    3,         -1,         0 ;
              dq   190,  310,      8,   0118811h,     50,    4,          0,         0 ;
              dq   540,  160,     10,   0B1A2D1h,     50,    5,          2,         0 ;
              dq   540,  160,     10,   0BB8888h,     50,    6,          1,         0 ;


   BgColorIsSet    db 0
   FrameCounter    dd ?
   GravCounter     db 0
   UpdateCounter   db 0

.CODE

;*********************************************************
;   Ball_DrawBoxXYR
;
;        Parameters: context
;                    x coordinate of center of box
;                    y coordinate of center of box
;                    radius of box (width and height / 2)
;                    color of box
;
;        Return Value: TRUE / FALSE.  FALSE only if nothing
;                could be drawn to the screen.
;
;
;*********************************************************  
NESTED_ENTRY Ball_DrawBoxXYR, _TEXT$00
 alloc_stack(SIZEOF TEMPLATE_FUNCTION_STRUCT)
 save_reg rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi
 save_reg rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi
 save_reg rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx
 save_reg r10, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR10
 save_reg r11, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR11
 save_reg r12, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR12
 save_reg r13, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR13
.ENDPROLOG 

  ; Store parameter1 (color of box)
  MOV RSI, [RSP+8+SIZEOF TEMPLATE_FUNCTION_STRUCT]
  MOV TEMPLATE_FUNCTION_STRUCT.ParameterFrame.Param1[RSP], RSI

  MOV RSI, RCX
  ; Registers at init...
  ;   rcx = context
  ;   rdx = x coord
  ;   r8  = y coord
  ;   r9  = 'radius'
  ; rsp+8 = color

  ; Registers used....
  ;   rax = current X
  ;   rbx = current Y
  ;   r9  = radius
  ;   paramFrame  = color

  ;
  ; Params checking phase.
  ; Initialize RAX and RBX to point to the top-left corner of a box
  ; containing the circle
  ;

  ; First set up the X coordinate starting point
  MOV RAX, RDX

  ; Check if our right edge is completely off the left side of the window
  ADD RAX, R9
  CMP RAX, 0
  JL @DrawBoxXYR_Finish  ; overflow is bad.

  ; Now lets just make sure our left edge isn't off the right side of the window
  SUB RAX, R9
  SUB RAX, R9
  MOV RDI, MASTER_DEMO_STRUCT.ScreenWidth[RSI]
  CMP RAX, RDI  ; no need to draw anything if we aren't on the screen
  JGE @DrawBoxXYR_Finish  ; error - no need to draw if we arent on screen.

  ; Make sure we draw at x= 0 if our left edge is out of bounds.
  xor R12, R12
  CMP RAX, R12
  CMOVLE RAX, R12

  ;
  ; Next set up the y coordinates
  ;
  MOV RBX, R8
  SUB RBX, R9
  CMP RBX, 0
  JL  @DrawBoxXYR_Finish  ; if bottom of box is less than zero, we give up.  Quit now!
  SHL R9, 1
  ADD RBX, R9
  MOV RDI, MASTER_DEMO_STRUCT.ScreenHeight[RSI]
  CMP RBX, RDI ; If top of box is greater than the height, we give up. Quit now!
  JGE @DrawBoxXYR_Finish

  ; Make sure we start at y=0 if the box's top edge is out of bounds
  CMP RBX, R12
  CMOVLE RBX, R12
  MOV R10, RAX

  ;
  ; Now R10 and RBX point to the top left corner.  R9 is diameter.
  ;

  MOV RDI, RAX
  SHL RDI, 2  ; first add the X coordinate in
  ADD RDI, MASTER_DEMO_STRUCT.VideoBuffer[RSI] ; setup frame buffer

  ;
  ; Calculate the starting Y coordinate into RDI (buffer location)
  ;
  MOV RAX, MASTER_DEMO_STRUCT.ScreenWidth[RSI]
  SHL RAX, 2
  IMUL RAX, RBX
  ADD RDI, RAX

  ;
  ; Set up loop params
  ;
  MOV R12, R9   ; loop counter. Number of vertical lines to try.
  ; TODO: ensure R12 doesnt loop so much that it goes off the screen


  MOV R13, RDI
  MOV RAX, TEMPLATE_FUNCTION_STRUCT.ParameterFrame.Param1[RSP] ; RAX <- Color
  
  ;
  ; Convert R9 to width of box, instead of radius. This way
  ; we will never write outside of the bounds of the buffer.
  ; Note that R10 is Xmin
  ;
  MOV R11, R10
  ADD R11, R9
  CMP R11, MASTER_DEMO_STRUCT.ScreenWidth[RSI]
  JL  @DrawBoxXYR_DoneGettingWidth

  ; If we are outside the width, then subtract the chunk outside.
  SUB R11, MASTER_DEMO_STRUCT.ScreenWidth[RSI]
  SUB R9, R11
  
  ;
  ; If R9 is zero, then maybe we got cropped!  
  ; TODO: Do one last check to make sure we dont write too much to
  ; the right of our box.
  ;

@DrawBoxXYR_DoneGettingWidth:

  ; TODO: Insert code to get number of vertical lines into R12 here & remove
  ; the work inside the painting loop below


  ;
  ; RDI shall contain the spot in the frame buffer we want to write to
  ;
  MOV RDI, R13

  ;
  ; Scan across each line horizontally, filling it in.
  ;
@DrawBoxXYR_BeginPaint:

  MOV RCX, R9  ;   RCX <- Width
  REP STOSD

  ;
  ; Wrap to the next line by adjusting for stride
  ;
  MOV RDX, MASTER_DEMO_STRUCT.ScreenWidth[RSI]
  SHL RDX, 2
  ADD RDI, RDX

  ;
  ; Undo the addition to RDI done by REP STOSD
  ;
  MOV RDX, R9
  SHL RDX, 2
  SUB RDI, RDX

  ;
  ; Increment for the next line
  ; TODO: Remove and put in a-priori calculation inside R12
  ;
  INC RBX
  CMP RBX, MASTER_DEMO_STRUCT.ScreenHeight[RSI]
  JGE @DrawBoxXYR_Finish_Success

  ;
  ; Decrement loop counter and bail if zero
  ;
  DEC R12
  JNZ @DrawBoxXYR_BeginPaint

  ;
  ; Finish with success
  ; 
@DrawBoxXYR_Finish_Success:
  MOV RAX, 1

@DrawBoxXYR_Finish:
  MOV rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi[RSP]
  MOV rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi[RSP]
  MOV rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx[RSP]

  MOV r10, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR10[RSP]
  MOV r11, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR11[RSP]
  MOV r12, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR12[RSP]
  MOV r13, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR13[RSP]
  ADD RSP, SIZE TEMPLATE_FUNCTION_STRUCT
  RET
NESTED_END Ball_DrawBoxXYR, _TEXT$00

;*********************************************************
;   Ball_BounceCorrect
;
;        Parameters: Pointer to BALL_INFO
;                    Velocity to change (0 for x, 1 for y)
;
;        Return Value: garbage
;
;
;*********************************************************  
NESTED_ENTRY Ball_BounceCorrect, _TEXT$00
 save_reg rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi
 save_reg rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi
 save_reg rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx
.ENDPROLOG

  MOV RDI, RCX  ; RDI <- BALL_INFO
  MOV RBX, RDX  ; RDX <- X or Y

  ; RSI shall hold Velocity
  MOV RSI, BALL_INFO.VelocityX[RDI]
  CMP RBX, 1
  JNE @Ball_BounceCorrect_GotVelocity
  MOV RSI, BALL_INFO.VelocityY[RDI]

@Ball_BounceCorrect_GotVelocity:

  ; Try to factor in bounce
  PUSH RBX
  XOR EDX, EDX
  MOV RAX, BALL_INFO.Bounciness[RDI]
  IMUL RAX, RSI ; EAX <- Bounciness * Velocity
  MOV RBX, MAX_BOUNCINESS ; 100
  DIV RBX
  MOV RSI, RAX
  POP RBX
  ; END factoring in bounce

  ; Reverse the velocity
  NEG RSI

  CMP RBX, 1
  JE @Ball_BounceCorrect_WriteVelocityY
  MOV BALL_INFO.VelocityX[RDI], RSI
  ADD BALL_INFO.X[RDI], RSI
  JMP @Ball_BounceCorrect_WroteVelocity

@Ball_BounceCorrect_WriteVelocityY:
  MOV BALL_INFO.VelocityY[RDI], RSI
  ADD BALL_INFO.Y[RDI], RSI

@Ball_BounceCorrect_WroteVelocity:


  MOV rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi[RSP]
  MOV rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi[RSP]
  MOV rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx[RSP]
  RET
NESTED_END Ball_BounceCorrect, _TEXT$00

;*********************************************************
;   Ball_UpdateBallPositions
;
;        Parameters: context
;                    array address
;                    number of balls in array
;
;        Return Value: TRUE / FALSE.  FALSE only if nothing
;                could be drawn to the screen.
;
;
;*********************************************************  
NESTED_ENTRY Ball_UpdateBallPositions, _TEXT$00
 alloc_stack(SIZEOF TEMPLATE_FUNCTION_STRUCT)
 save_reg rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi
 save_reg r10, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR10
 save_reg r11, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR11
 save_reg r12, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR12
 save_reg r13, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR13
.ENDPROLOG 

  MOV R10, RCX   ; R10 <- Context
  MOV R11, RDX   ; R11 <- ArrayAddress
  MOV R12, R8    ; R12 <- ArrayCount

  ;
  ; 1. Loop through entire array, undrawing balls
  ;

  MOV RDI, R11   ; Start of our array
  MOV R13, R12   ; R13 <- LoopCount (number of balls)

@UpdateBallPositions_UndrawABall:
 
  XOR RCX, RCX
  MOV ECX, [BackgroundColor]
  PUSH RCX
  MOV RCX, R10
  MOV RDX, BALL_INFO.X[RDI]
  MOV R8, BALL_INFO.Y[RDI]
  MOV R9, BALL_INFO.Radius[RDI]
  CALL Ball_DrawBoxXYR
  ADD RSP, 8

  ADD RDI, SIZEOF BALL_INFO
  DEC R13
  JNZ @UpdateBallPositions_UndrawABall


  ;
  ; 2. Update positions for each ball.
  ;

  MOV RDI, R11   ; Start of our array
  MOV R13, R12   ; R13 <- LoopCount (number of balls)

@UpdateBallPositions_UpdateABallPositionData:

  MOV RDX, BALL_INFO.X[RDI]
  MOV R8, BALL_INFO.Y[RDI]
  MOV R9, BALL_INFO.Radius[RDI]

  ;
  ; First update all coordinates
  ;
  ADD RDX, BALL_INFO.VelocityX[RDI]
  MOV BALL_INFO.X[RDI], RDX

  MOV RDX, BALL_INFO.VelocityY[RDI]

  ; Update gravity
  ADD [GravCounter], 1
  CMP [GravCounter], GRAV_DIVISOR
  JL @UpdateBallPositions_GravityCalculationDone
  ADD RDX, GRAVITY
  MOV [GravCounter], 0
  MOV BALL_INFO.VelocityY[RDI], RDX

  ; Update Y position
@UpdateBallPositions_GravityCalculationDone:
  ADD R8, RDX
  MOV BALL_INFO.Y[RDI], R8

  ;
  ; Check coordinates now.
  ; If Y - Radius is less than zero, we bounced off the top
  ; 

  MOV RCX, MASTER_DEMO_STRUCT.ScreenHeight[R10]
  SUB RCX, BALL_INFO.Y[RDI]
  SUB RCX, R9
  CMP RCX, 0
  JAE @UpdateBallPositions_CheckYBottom

  ; Fall through to correct bouncing off the top
  MOV RCX, RDI
  MOV RDX, 1
  CALL Ball_BounceCorrect

@UpdateBallPositions_CheckYBottom:
  MOV RCX, BALL_INFO.Y[RDI]
  ADD RCX, R9
  CMP RCX, MASTER_DEMO_STRUCT.ScreenHeight[R10]
  JLE @UpdateBallPositions_CheckXLeftSide

  ; fall through to correct bouncing off the bottom
  MOV RCX, RDI
  MOV RDX, 1
  CALL Ball_BounceCorrect

@UpdateBallPositions_CheckXLeftSide:
  MOV RCX, MASTER_DEMO_STRUCT.ScreenWidth[R10]
  SUB RCX, BALL_INFO.X[RDI]
  SUB RCX, R9
  CMP RCX, 0
  JGE @UpdateBallPositions_CheckXRightSide

  MOV RCX, RDI
  MOV RDX, 0
  CALL Ball_BounceCorrect

@UpdateBallPositions_CheckXRightSide:
  MOV RCX, BALL_INFO.X[RDI]
  ADD RCX, R9
  CMP RCX, MASTER_DEMO_STRUCT.ScreenWidth[R10]
  JLE @UpdateBallPositions_SkipCorrectionXRightSide

  MOV RCX, RDI
  MOV RDX, 0
  CALL Ball_BounceCorrect


@UpdateBallPositions_SkipCorrectionXRightSide:

  ; Try again if there are more balls
  ADD RDI, SIZEOF BALL_INFO
  DEC R13
  JNZ @UpdateBallPositions_UpdateABallPositionData


  ;
  ; 3. Lastly we must redraw all the balls in Z order
  ;

  MOV RDI, R11
  MOV RAX, SIZEOF BALL_INFO
  IMUL RAX, NUM_BALLS
  ADD RDI, RAX
  SUB RDI, SIZEOF BALL_INFO
  MOV R13, R12

@UpdateBallPositions_DrawABall:

  ;   rcx = context
  ;   rdx = x coord
  ;   r8  = y coord
  ;   r9  = 'radius'
  ; rsp+8 = color
  MOV RCX, BALL_INFO.Color[RDI]
  PUSH RCX
  MOV RCX, R10
  MOV RDX, BALL_INFO.X[RDI]
  MOV R8, BALL_INFO.Y[RDI]
  MOV R9, BALL_INFO.Radius[RDI]
  CALL Ball_DrawBoxXYR
  ADD RSP, 8

  SUB RDI, SIZEOF BALL_INFO
  DEC R13
  JNZ @UpdateBallPositions_DrawABall


@UpdateBallPositions_Finish:
  MOV rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi[RSP]
  MOV r10, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR10[RSP]
  MOV r11, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR11[RSP]
  MOV r12, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR12[RSP]
  MOV r13, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR13[RSP]
  ADD RSP, SIZE TEMPLATE_FUNCTION_STRUCT
  RET

NESTED_END Ball_UpdateBallPositions, _TEXT$00



;*********************************************************
;   Ball_SetBackgroundColor
;
;        Parameters: Master Context
;                    Color
;
;        Return Value: TRUE / FALSE
;
;
;*********************************************************  
NESTED_ENTRY Ball_SetBackgroundColor, _TEXT$00
 alloc_stack(SIZEOF TEMPLATE_FUNCTION_STRUCT)
 save_reg rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi
 save_reg rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi
 save_reg rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx
.ENDPROLOG 

  MOV RSI, RCX

  ;
  ; Get the Video Buffer
  ; 
  MOV RDI, MASTER_DEMO_STRUCT.VideoBuffer[RSI]


  MOV RAX, RDX
  AND RAX, 0FFFFFFh
  MOV RDX, MASTER_DEMO_STRUCT.ScreenHeight[RSI]

@SetBackground_PlotLineColor:
  MOV RCX, MASTER_DEMO_STRUCT.ScreenWidth[RSI]
  REP STOSD

  ;
  ; Wrap to the next line by adjusting for stride
  ;
  XOR RBX, RBX
  MOV EBX, MASTER_DEMO_STRUCT.Pitch[RSI]
  MOV R8, MASTER_DEMO_STRUCT.ScreenWidth[RSI]
  SHL R8, 2
  SUB RBX, R8
  ADD RDI, RBX

  ;
  ; Decrement for the next line
  ;
  DEC RDX
  JNZ @SetBackground_PlotLineColor


  MOV RSI, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi[RSP]
  MOV RDI, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi[RSP]
  MOV RBX, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx[RSP]
  ADD RSP, SIZE TEMPLATE_FUNCTION_STRUCT
  MOV EAX, 1
  RET
NESTED_END Ball_SetBackgroundColor, _TEXT$00



;*********************************************************
;   Ball_Init
;
;        Parameters: Master Context
;
;        Return Value: TRUE / FALSE
;
;
;*********************************************************  
NESTED_ENTRY Ball_Init, _TEXT$00
 alloc_stack(SIZEOF TEMPLATE_FUNCTION_STRUCT)
 save_reg rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi
 save_reg rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi
.ENDPROLOG 

  MOV [FrameCounter], 0

  ;
  ; Initialize Random Numbers
  ;
  XOR ECX, ECX
  CALL time
  MOV ECX, EAX
  CALL srand

  MOV RSI, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi[RSP]
  MOV RDI, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi[RSP]
  ADD RSP, SIZE TEMPLATE_FUNCTION_STRUCT
  MOV EAX, 1
  RET
NESTED_END Ball_Init, _TEXT$00



;*********************************************************
;  Ball_Demo
;
;        Parameters: Master Context
;
;        Return Value: TRUE / FALSE    
;
;
;*********************************************************  
NESTED_ENTRY Ball_Demo, _TEXT$00
 alloc_stack(SIZEOF TEMPLATE_FUNCTION_STRUCT)
 save_reg rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi
 save_reg rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi
 save_reg rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx
 save_reg r10, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR10
 save_reg r11, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR11
 save_reg r12, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR12
 save_reg r13, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR13

.ENDPROLOG 
  
  MOV RSI, RCX

  ;
  ; Only set the background color once.
  ; Note that we cant do this in the init function since we
  ; dont have access to graphics yet.
  ;
  XOR RAX, RAX
  CMP AL, [BgColorIsSet]
  JNE @BallDemo_BgColorHasBeenSet
  MOV EAX, [BackgroundColor]
  MOV RCX, RSI
  MOV RDX, RAX
  CALL Ball_SetBackgroundColor
  ADD [BgColorIsSet], 1

@BallDemo_BgColorHasBeenSet:

  ADD [UpdateCounter], 1
  CMP [UpdateCounter], UPDATE_DIVISOR
  JLE @BallDemo_Done_Drawing_Balls
  MOV [UpdateCounter], 0

  MOV RCX, RSI
  LEA RDX, [BallArray]
  MOV R8, NUM_BALLS
  CALL Ball_UpdateBallPositions

@BallDemo_Done_Drawing_Balls:

  ;
  ; Update the frame counter and determine if the demo is complete.
  ;
  XOR EAX, EAX
  INC [FrameCounter]
  CMP [FrameCounter], MAX_FRAMES
  SETE AL
  XOR AL, 1
 
  MOV rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi[RSP]
  MOV rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi[RSP]
  MOV rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx[RSP]

  MOV r10, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR10[RSP]
  MOV r11, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR11[RSP]
  MOV r12, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR12[RSP]
  MOV r13, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveR13[RSP]

  ADD RSP, SIZE TEMPLATE_FUNCTION_STRUCT
  RET
NESTED_END Ball_Demo, _TEXT$00



;*********************************************************
;  Ball_Free
;
;        Parameters: Master Context
;
;       
;
;
;*********************************************************  
NESTED_ENTRY Ball_Free, _TEXT$00
 alloc_stack(SIZEOF TEMPLATE_FUNCTION_STRUCT)
 save_reg rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi
 save_reg rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi
 save_reg rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx
.ENDPROLOG 

  ; Nothing to clean up

  MOV rdi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRdi[RSP]
  MOV rsi, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRsi[RSP]
  MOV rbx, TEMPLATE_FUNCTION_STRUCT.SaveFrame.SaveRbx[RSP]

  ADD RSP, SIZE TEMPLATE_FUNCTION_STRUCT
  RET
NESTED_END Ball_Free, _TEXT$00


END
