/*
 * linux/arch/arm/mach-omap3/sram.S
 *
 * Omap3 specific functions that need to be run in internal SRAM
 *
 * Copyright (C) 2004, 2007, 2008 Texas Instruments, Inc.
 * Copyright (C) 2008 Nokia Corporation
 *
 * Rajendra Nayak <rnayak@ti.com>
 * Richard Woodruff <r-woodruff2@ti.com>
 * Paul Walmsley
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR /PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */
#include <linux/linkage.h>
#include <asm/assembler.h>
#include <mach/hardware.h>

#include <mach/io.h>

#include "sdrc.h"
#include "cm.h"

	.text

/* r1 parameters */
#define SDRC_NO_UNLOCK_DLL		0x0
#define SDRC_UNLOCK_DLL			0x1

/* SDRC_DLLA_CTRL bit settings */
#define FIXEDDELAY_SHIFT		24
#define FIXEDDELAY_MASK			(0xff << FIXEDDELAY_SHIFT)
#define DLLIDLE_MASK			0x4

/*
 * SDRC_DLLA_CTRL default values: TI hardware team indicates that
 * FIXEDDELAY should be initialized to 0xf.  This apparently was
 * empirically determined during process testing, so no derivation
 * was provided.
 */
#define FIXEDDELAY_DEFAULT		(0x0f << FIXEDDELAY_SHIFT)

/* SDRC_DLLA_STATUS bit settings */
#define LOCKSTATUS_MASK			0x4

/* SDRC_POWER bit settings */
#define SRFRONIDLEREQ_MASK		0x40

/* CM_IDLEST1_CORE bit settings */
#define ST_SDRC_MASK			0x2

/* CM_ICLKEN1_CORE bit settings */
#define EN_SDRC_MASK			0x2

/* CM_CLKSEL1_PLL bit settings */
#define CORE_DPLL_CLKOUT_DIV_SHIFT	0x1b

/* DSS registers */
#define OMAP34XX_DISPC_BASE		0x48050400
#define DISPC_CONTROL			OMAP2_L4_IO_ADDRESS(OMAP34XX_DISPC_BASE + 0x040)
#define DISPC_IRQSTATUS			OMAP2_L4_IO_ADDRESS(OMAP34XX_DISPC_BASE + 0x018)
#define DISPC_LCD_EN			(1 << 0)
#define DISPC_VSYNC_ST			(1 << 1)
#define DISPC_FRMDNE_ST			(1 << 0)
#define CM_DSS_FCLK_ST			(1 << 0)

/*
 * omap3_sram_configure_core_dpll - change DPLL3 M2 divider
 *
 * Params passed in registers:
 *  r0 = new M2 divider setting (only 1 and 2 supported right now)
 *  r1 = unlock SDRC DLL? (1 = yes, 0 = no).  Only unlock DLL for
 *      SDRC rates < 83MHz
 *  r2 = number of MPU cycles to wait for SDRC to stabilize after
 *      reprogramming the SDRC when switching to a slower MPU speed
 *  r3 = increasing SDRC rate? (1 = yes, 0 = no)
 *
 * Params passed via the stack. The needed params will be copied in SRAM
 *  before use by the code in SRAM (SDRAM is not accessible during SDRC
 *  reconfiguration):
 *  new SDRC_RFR_CTRL_0 register contents
 *  new SDRC_ACTIM_CTRL_A_0 register contents
 *  new SDRC_ACTIM_CTRL_B_0 register contents
 *  new SDRC_MR_0 register value
 *  new SDRC_RFR_CTRL_1 register contents
 *  new SDRC_ACTIM_CTRL_A_1 register contents
 *  new SDRC_ACTIM_CTRL_B_1 register contents
 *  new SDRC_MR_1 register value
 *
 * If the param SDRC_RFR_CTRL_1 is 0, the parameters are not programmed into
 * the SDRC CS1 registers
 *
 * NOTE: This code no longer attempts to program the SDRC AC timing and MR
 * registers.  This is because the code currently cannot ensure that all
 * L3 initiators (e.g., sDMA, IVA, DSS DISPC, etc.) are not accessing the
 * SDRAM when the registers are written.  If the registers are changed while
 * an initiator is accessing SDRAM, memory can be corrupted and/or the SDRC
 * may enter an unpredictable state.  In the future, the intent is to
 * re-enable this code in cases where we can ensure that no initiators are
 * touching the SDRAM.  Until that time, users who know that their use case
 * can satisfy the above requirement can enable the CONFIG_OMAP3_SDRC_AC_TIMING
 * option.
 */
ENTRY(omap3_sram_configure_core_dpll)
	stmfd	sp!, {r1-r12, lr}	@ store regs to stack

					@ pull the extra args off the stack
					@  and store them in SRAM
	ldr	r4, [sp, #52]
	str     r4, omap_sdrc_rfr_ctrl_0_val
	ldr	r4, [sp, #56]
	str     r4, omap_sdrc_actim_ctrl_a_0_val
	ldr	r4, [sp, #60]
	str     r4, omap_sdrc_actim_ctrl_b_0_val
	ldr	r4, [sp, #64]
	str     r4, omap_sdrc_mr_0_val
	ldr	r4, [sp, #68]
	str     r4, omap_sdrc_rfr_ctrl_1_val
	cmp	r4, #0			@ if SDRC_RFR_CTRL_1 is 0,
	beq	skip_cs1_params		@  do not use cs1 params
	ldr	r4, [sp, #72]
	str     r4, omap_sdrc_actim_ctrl_a_1_val
	ldr	r4, [sp, #76]
	str     r4, omap_sdrc_actim_ctrl_b_1_val
	ldr	r4, [sp, #80]
	str     r4, omap_sdrc_mr_1_val
skip_cs1_params:
	dsb				@ flush buffered writes to interconnect

	ldr	r11, omap3_cm_fclk_dss
	ldr	r12, [r11]
	and	r12, r12, #CM_DSS_FCLK_ST
	cmp	r12, #CM_DSS_FCLK_ST	@ check if dss fclk is active
	blne	configure_dpll
	ldr	r11, omap3_dispc_ctrl
	ldr	r12, [r11]
	and	r12, r12, #DISPC_LCD_EN
	cmp	r12, #DISPC_LCD_EN	@ check if lcd is enabled
	blne	configure_dpll
	ldr	r11, omap3_dispc_irq_st
	ldr	r12, [r11]
	and	r12, r12, #DISPC_FRMDNE_ST	@ clear framedone
	str	r12, [r11]
wait_vsync_set:
	ldr	r12, [r11]
	and	r12, r12, #DISPC_FRMDNE_ST
	cmp	r12, #DISPC_FRMDNE_ST
	blne	wait_vsync_set		@ wait for framedone to be set.
configure_dpll:
	cmp	r3, #1			@ if increasing SDRC clk rate,
	bleq	configure_sdrc		@ program the SDRC regs early (for RFR)
	cmp	r1, #SDRC_UNLOCK_DLL	@ set the intended DLL state
	bleq	unlock_dll
	blne	lock_dll
	bl	sdram_in_selfrefresh	@ put SDRAM in self refresh, idle SDRC
	bl 	configure_core_dpll	@ change the DPLL3 M2 divider
	mov	r12, r2
	bl	wait_clk_stable		@ wait for SDRC to stabilize
	bl	enable_sdrc		@ take SDRC out of idle
	cmp	r1, #SDRC_UNLOCK_DLL	@ wait for DLL status to change
	bleq	wait_dll_unlock
	blne	wait_dll_lock
	cmp	r3, #1			@ if increasing SDRC clk rate,
	beq	return_to_sdram		@ return to SDRAM code, otherwise,
	bl	configure_sdrc		@ reprogram SDRC regs now
return_to_sdram:
	isb				@ prevent speculative exec past here
	mov 	r0, #0 			@ return value
	ldmfd	sp!, {r1-r12, pc}	@ restore regs and return
unlock_dll:
	ldr	r11, omap3_sdrc_dlla_ctrl
	ldr	r12, [r11]
	bic	r12, r12, #FIXEDDELAY_MASK
	orr	r12, r12, #FIXEDDELAY_DEFAULT
	orr	r12, r12, #DLLIDLE_MASK
	str	r12, [r11]		@ (no OCP barrier needed)
	bx	lr
lock_dll:
	ldr	r11, omap3_sdrc_dlla_ctrl
	ldr	r12, [r11]
	bic	r12, r12, #DLLIDLE_MASK
	str	r12, [r11]		@ (no OCP barrier needed)
	bx	lr
sdram_in_selfrefresh:
	ldr	r11, omap3_sdrc_power	@ read the SDRC_POWER register
	ldr	r12, [r11]		@ read the contents of SDRC_POWER
	mov	r9, r12			@ keep a copy of SDRC_POWER bits
	orr 	r12, r12, #SRFRONIDLEREQ_MASK	@ enable self refresh on idle
	str 	r12, [r11]		@ write back to SDRC_POWER register
	ldr	r12, [r11]		@ posted-write barrier for SDRC
idle_sdrc:
	ldr	r11, omap3_cm_iclken1_core	@ read the CM_ICLKEN1_CORE reg
	ldr	r12, [r11]
	bic	r12, r12, #EN_SDRC_MASK		@ disable iclk bit for SDRC
	str 	r12, [r11]
wait_sdrc_idle:
	ldr 	r11, omap3_cm_idlest1_core
	ldr 	r12, [r11]
	and 	r12, r12, #ST_SDRC_MASK		@ check for SDRC idle
	cmp 	r12, #ST_SDRC_MASK
	bne 	wait_sdrc_idle
	bx 	lr
configure_core_dpll:
	ldr 	r11, omap3_cm_clksel1_pll
	ldr	r12, [r11]
	ldr	r10, core_m2_mask_val	@ modify m2 for core dpll
	and	r12, r12, r10
	orr	r12, r12, r0, lsl #CORE_DPLL_CLKOUT_DIV_SHIFT
	str	r12, [r11]
	ldr	r12, [r11]		@ posted-write barrier for CM
	bx	lr
wait_clk_stable:
	subs 	r12, r12, #1
	bne	wait_clk_stable
	bx	lr
enable_sdrc:
	ldr 	r11, omap3_cm_iclken1_core
	ldr	r12, [r11]
	orr 	r12, r12, #EN_SDRC_MASK		@ enable iclk bit for SDRC
	str 	r12, [r11]
wait_sdrc_idle1:
	ldr 	r11, omap3_cm_idlest1_core
	ldr	r12, [r11]
	and 	r12, r12, #ST_SDRC_MASK
	cmp	r12, #0
	bne	wait_sdrc_idle1
restore_sdrc_power_val:
	ldr	r11, omap3_sdrc_power
	str	r9, [r11]		@ restore SDRC_POWER, no barrier needed
	bx	lr
wait_dll_lock:
	ldr	r11, omap3_sdrc_dlla_status
	ldr	r12, [r11]
	and 	r12, r12, #LOCKSTATUS_MASK
	cmp	r12, #LOCKSTATUS_MASK
	bne	wait_dll_lock
	bx	lr
wait_dll_unlock:
	ldr	r11, omap3_sdrc_dlla_status
	ldr	r12, [r11]
	and	r12, r12, #LOCKSTATUS_MASK
	cmp	r12, #0x0
	bne	wait_dll_unlock
	bx	lr
configure_sdrc:
	ldr	r12, omap_sdrc_rfr_ctrl_0_val	@ fetch value from SRAM
	ldr	r11, omap3_sdrc_rfr_ctrl_0	@ fetch addr from SRAM
	str	r12, [r11]			@ store
#ifdef CONFIG_OMAP3_SDRC_AC_TIMING
	ldr	r12, omap_sdrc_actim_ctrl_a_0_val
	ldr	r11, omap3_sdrc_actim_ctrl_a_0
	str	r12, [r11]
	ldr	r12, omap_sdrc_actim_ctrl_b_0_val
	ldr	r11, omap3_sdrc_actim_ctrl_b_0
	str	r12, [r11]
	ldr	r12, omap_sdrc_mr_0_val
	ldr	r11, omap3_sdrc_mr_0
	str	r12, [r11]
#endif
	ldr	r12, omap_sdrc_rfr_ctrl_1_val
	cmp	r12, #0			@ if SDRC_RFR_CTRL_1 is 0,
	beq	skip_cs1_prog		@  do not program cs1 params
	ldr	r11, omap3_sdrc_rfr_ctrl_1
	str	r12, [r11]
#ifdef CONFIG_OMAP3_SDRC_AC_TIMING
	ldr	r12, omap_sdrc_actim_ctrl_a_1_val
	ldr	r11, omap3_sdrc_actim_ctrl_a_1
	str	r12, [r11]
	ldr	r12, omap_sdrc_actim_ctrl_b_1_val
	ldr	r11, omap3_sdrc_actim_ctrl_b_1
	str	r12, [r11]
	ldr	r12, omap_sdrc_mr_1_val
	ldr	r11, omap3_sdrc_mr_1
	str	r12, [r11]
#endif
skip_cs1_prog:
	ldr	r12, [r11]		@ posted-write barrier for SDRC
	bx	lr

omap3_sdrc_power:
	.word OMAP34XX_SDRC_REGADDR(SDRC_POWER)
omap3_cm_clksel1_pll:
	.word OMAP34XX_CM_REGADDR(PLL_MOD, CM_CLKSEL1)
omap3_cm_idlest1_core:
	.word OMAP34XX_CM_REGADDR(CORE_MOD, CM_IDLEST)
omap3_cm_iclken1_core:
	.word OMAP34XX_CM_REGADDR(CORE_MOD, CM_ICLKEN1)

omap3_sdrc_rfr_ctrl_0:
	.word OMAP34XX_SDRC_REGADDR(SDRC_RFR_CTRL_0)
omap3_sdrc_rfr_ctrl_1:
	.word OMAP34XX_SDRC_REGADDR(SDRC_RFR_CTRL_1)
omap3_sdrc_actim_ctrl_a_0:
	.word OMAP34XX_SDRC_REGADDR(SDRC_ACTIM_CTRL_A_0)
omap3_sdrc_actim_ctrl_a_1:
	.word OMAP34XX_SDRC_REGADDR(SDRC_ACTIM_CTRL_A_1)
omap3_sdrc_actim_ctrl_b_0:
	.word OMAP34XX_SDRC_REGADDR(SDRC_ACTIM_CTRL_B_0)
omap3_sdrc_actim_ctrl_b_1:
	.word OMAP34XX_SDRC_REGADDR(SDRC_ACTIM_CTRL_B_1)
omap3_sdrc_mr_0:
	.word OMAP34XX_SDRC_REGADDR(SDRC_MR_0)
omap3_sdrc_mr_1:
	.word OMAP34XX_SDRC_REGADDR(SDRC_MR_1)
omap_sdrc_rfr_ctrl_0_val:
	.word 0xDEADBEEF
omap_sdrc_rfr_ctrl_1_val:
	.word 0xDEADBEEF
omap_sdrc_actim_ctrl_a_0_val:
	.word 0xDEADBEEF
omap_sdrc_actim_ctrl_a_1_val:
	.word 0xDEADBEEF
omap_sdrc_actim_ctrl_b_0_val:
	.word 0xDEADBEEF
omap_sdrc_actim_ctrl_b_1_val:
	.word 0xDEADBEEF
omap_sdrc_mr_0_val:
	.word 0xDEADBEEF
omap_sdrc_mr_1_val:
	.word 0xDEADBEEF

omap3_sdrc_dlla_status:
	.word OMAP34XX_SDRC_REGADDR(SDRC_DLLA_STATUS)
omap3_sdrc_dlla_ctrl:
	.word OMAP34XX_SDRC_REGADDR(SDRC_DLLA_CTRL)
core_m2_mask_val:
	.word 0x07FFFFFF
omap3_cm_fclk_dss:
	.word OMAP34XX_CM_REGADDR(OMAP3430_DSS_MOD, CM_FCLKEN)
omap3_dispc_ctrl:
	.word DISPC_CONTROL
omap3_dispc_irq_st:
	.word DISPC_IRQSTATUS

ENTRY(omap3_sram_configure_core_dpll_sz)
	.word	. - omap3_sram_configure_core_dpll

