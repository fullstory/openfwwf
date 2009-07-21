/*
*  BCM43xx device microcode
*   For Wireless-Core Revision 5
*
*  Copyright (C) 2009		University of Brescia
*
*  Copyright (C) 2008, 2009	Lorenzo Nava <navalorenx@gmail.com>
*				Francesco Gringoli <francesco.gringoli@ing.unibs.it>						
*  Copyright (C) 2008  		Michael Buesch <mb@bu3sch.de>
*
*   This program is free software; you can redistribute it and/or
*   modify it under the terms of the GNU General Public License
*   version 2, as published by the Free Software Foundation.
*
*   This program is distributed in the hope that it will be useful,
*   but WITHOUT ANY WARRANTY; without even the implied warranty of
*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*   GNU General Public License for more details.
*/

// a few notes for beginners
//
// 1) this is very important: when removing bytes or copying from FIFO to somewhere
//    bytes are copied on 32bit boundaries.
//    So you cannot remove or copy 39 byte, the effect is to remove or copy 40 bytes!
//
// 2) when removing and copying bytes from FIFO to SHM you should carefully verify that
//    the number of bytes left after the copy is greater than 4. Otherwise the system becomes
//    unstable!!
//
// 3) expiration of ack timeout enables COND_TX_PMQ so that handler tx_contention_params_update
//    is invoked
//
// 4) remember to read clock info from SPR_TSF_WORDn always starting from the least significant bits
//    So if you want to read SPR_TSF_WORD1 and SPR_TSF_WORD0 READ first SPR_TSF_WORD0 and then SPR_TSF_WORD1
//
// when a frame that needs to be acknowledged is received by rx_[stuff], the NEED_RESPONSEFR bit is
// set in SPR_BRC. This will trigger the condition COND_NEED_RESPONSEFR
// that will be honoured by tx_frame_now that will send and ACK frame.
//
// Attention: condition COND_FRAME_NEED_ACK instead evaluates true when
// the current frame that is being transmitted needs an ack: in this case
// we will transmit the frame and verify that it will be received within
// a timeout interval. The need for transmit a frame and verify that
// an ack will be received is determined inside the tx_frame_now function
// in the find_tx_frame_type section: if needed the section compute_expected_response
// will be executed so that the FRAME_NEED_ACK bit will be set in SPR_BRC.
// 

// explanation for SPR_RXE_FIFOCTL
// the fifo queue is filled with an rxheader copied from shm, the frame received
// from air and the fcs. push_frame_into_fifo performs this operation
//
// air-buffer for incoming bytes from air
//     ||         ||
//     ||         \/
//     ||      rx-buffer => FIFO to host =====> dma => host
//     ||                    /\
//     \/                    ||
//  copy in SHM        SHM with header
//
// bit 0x0800: it seems to be always set
// bit 0x0020: if set will align the frame in the rx-buffer on a 4 byte boundary after the header copied from shm
// bit 0x0010: reset: when set the rx-buffer is flushed.
// bit 0x0004: when set the air-buffer is flushed. Probably also the rooms dedicated to decode the PLCP and
//             that raise the COND_RX_PLCP are flushed. Flushing complete when it is automatically switched back
//             to zero.
//             It is read when plcp is decoded to be sure that flushing is not going.
// bit 0x0002: when set, the rx buffer is filled with bytes coming from the air-buffer
//             copying those already present in the air-buffer
// bit 0x0001: when set advance the rx buffer to the queue copying also the header and the fcs
//
//

// explanation for SPR_RXE_0x1a, something related to the pair of air-buffer and rx-buffer
//
// bit 0x8000: rxe is in overflow
// bit 0x4000: after COND_RX_COMPLETE is true, transition from 0 to 1 signals that all bytes have been copied
//             to the rx-buffer (?), if this is true, i'm not sure, the same does not apply to the copy in shm
//             (to the area pointed by SPR_RXE_Copy_Offset and whose length is given by SPR_RXE_Copy_Length)
// bit 0x1000: ?? it seems that we should verify it is zero before handling rx_badplcp
// bit 0x0800: when set the handler rx_badplcp should delay
// bit 0x0080: ?? used to skip to set a bit in GLOBAL_FLAGS_REG2 when it is not zero in tx_timers_setup


	#include "spr.inc"
	#include "shm.inc"
	#include "cond.inc"
	#include "myreg.inc"

	#define		TS_DATA			0x002
	#define		TS_ACK			0x035
	#define		TS_CTS			0x031
	#define		TS_RTS			0x02D	
	#define		TS_PSPOLL		0x029
	#define		TS_BEACON		0x020
	#define		TS_PROBE_REQ		0x010
	#define		TS_PROBE_RESP		0x014
	#define		TS_ASSOC_REQ		0x000
	#define		TS_REASSOC_REQ		0x008
	#define		TS_AUTH			0x02C
	#define		TS_ATIM			0x024

	#define		DEFAULT_MAX_CW		0x03FF
	#define		DEFAULT_MIN_CW		0x001F
	#define		DEFAULT_RETRY_LIMIT	0x0007

	%arch 5;
	
		mov	0, SPR_GPIO_OUT;					/* Disable any GPIO pin */			

// ***********************************************************************************************
// HANDLER:	init
// PURPOSE:	Initializes the device.
//
	init:;
		mov	0, SPR_PSM_0x4e;			
		mov	0, SPR_PSM_0x0c;						
		orx	0, 1, 0x001, SPR_PHY_HDR_Parameter, SPR_PHY_HDR_Parameter; 	/* SPR_PHY_HDR_Parameter = MAC_PHY_CLOCK_EN | (SPR_PHY_HDR_Parameter & ~MAC_PHY_CLOCK_EN) */
		jnzx	0, 5, SPR_MAC_CMD, 0x000, do_not_erase_shm;
		mov	0x07FF, SPR_BASE5;				
	erase_shm:;									/* loop through every register */
		mov	0, [0x00,off5];			
		sub	SPR_BASE5, 0x001, SPR_BASE5;				
		jges	SPR_BASE5, 0x000, erase_shm;
	do_not_erase_shm:;
		mov	0x1, [SHM_UCODESTAT];			
		mov	0, GP_REG5;				
		call	lr0, sel_phy_reg;					
		srx	7, 0, SPR_Ext_IHR_Data, 0x000, [SHM_PHYVER];		
		srx	3, 8, SPR_Ext_IHR_Data, 0x000, [SHM_PHYTYPE];		
		mov	0xFC00, [SHM_PRPHYCTL];			
		mov	0x2, SPR_PHY_HDR_Parameter;						
		mov	0, ANTENNA_DIVERSITY_CTR;				
		mov	0, GPHY_SYM_WAR_FLAG;				
		mov	0, GLOBAL_FLAGS_REG2;				
		mov	0xFF00, [SHM_ACKCTSPHYCTL];				
	        mov	0x019A, [SHM_UCODEREV]
	        mov	0x0870, [SHM_UCODEPATCH]
        	mov	0xFFFF, [SHM_UCODEDATE]
        	mov	0x7C0A, [SHM_UCODETIME]
	        mov	0, [SHM_PCTLWDPOS]
		mov	SHM_RXHEADER, SPR_BASE1;	// rx header starts @ 0xa10: buffer never accessed by b43 driver, can be moved!				
		mov	SHM_TXHEADER, SPR_BASE0;	// tx header starts @ 0x858: buffer never accessed by b43 driver, can be moved!
		mov	DEFAULT_RETRY_LIMIT, SHORT_RETRY_LIMIT;
		mov	DEFAULT_MAX_CW, MAX_CONTENTION_WIN;
		mov	DEFAULT_MIN_CW, MIN_CONTENTION_WIN;				
		or	MIN_CONTENTION_WIN, 0x000, CUR_CONTENTION_WIN;						
		and	SPR_TSF_Random, MIN_CONTENTION_WIN, SPR_IFS_BKOFFDELAY;	
		mov	0, SHORT_RETRIES;
		mov	0, LONG_RETRIES;				
		mov	0, GP_REG12;
		jext	COND_TRUE, mac_suspend;

// ***********************************************************************************************
// HANDLER:	state_machine_start
// PURPOSE:	Checks conditions looking for something to do. If there is no coming job firmware sleeps for a while or suspends device. 
//
	state_machine_idle:;
		mov	0, WATCHDOG			
		jnzx	0, 3, GLOBAL_FLAGS_REG3, 0x000, state_machine_start;	/* This bit was set and reset in bg_noise_sample */	
		jnzx	0, 9, [SHM_HF_MI], 0x000, state_machine_start;		
		mov	0xFFFF, SPR_MAC_MAX_NAP;				/* Sleep for a while.. */
		nap;								

	state_machine_start:;		
		jnext	EOI(COND_RADAR), no_radar_workaround;					
		jzx	0, 13, [SHM_HF_LO], 0x000, no_radar_workaround;		/* if (!(shm_host_flags_1 & MHF_RADARWAR)) */				
		mov	0x00C8, GP_REG5;					/* GP_REG5 = APHY_RADAR_THRESH1 */
		or	[SHM_RADAR], 0x000, GP_REG6;				/* write [SHM_RADAR] into GP_REG5 */
		call	lr0, write_phy_reg;					
	no_radar_workaround:;
		extcond_eoi_only(COND_PHY0);
		extcond_eoi_only(COND_PHY1);					
		orx	1, 3, 0x000, GLOBAL_FLAGS_REG2, GLOBAL_FLAGS_REG2;	/* clear bits 0x18 */				
		jzx	0, 3, SPR_IFS_STAT, 0x000, check_mac_status;		/* if (!(SPR_IFS_STAT & 0x08)) */	
		orx	1, 1, 0x000, GLOBAL_FLAGS_REG2, GLOBAL_FLAGS_REG2;	/* GLOBAL_FLAGS_REG2 & ~AFTERBURNER_TX|AFTERBURNER_RX */
		or	[SHM_GCLASSCTL], 0x000, GP_REG6;				
		call	lr1, gphy_classify_control_with_arg;			/* Classify control from SHM to PHY */
	check_mac_status:;							
		jnext	COND_MACEN, mac_suspend_check;				/* Check if we can sleep */		
		jext	COND_TX_FLUSH, check_conditions;

	check_conditions:;
		jext	EOI(COND_TX_NOW), tx_frame_now;				
		jext	EOI(COND_TX_POWER), tx_infos_update;				
		jext	EOI(COND_TX_UNDERFLOW), tx_underflow;			
		jext	COND_TX_DONE, tx_end_wait_10us;					

	check_conditions_no_tx:;
		jext	COND_TX_PHYERR, tx_phy_error;

	check_rx_conditions:;
		jext	EOI(COND_RX_WME8), tx_timers_setup;				
		jext	EOI(COND_RX_PLCP), rx_plcp;				
		jext	COND_RX_COMPLETE, rx_complete;				
		jext	COND_TX_PMQ, tx_contention_params_update;					
		jext	EOI(COND_RX_BADPLCP), rx_badplcp;			
		jnext	COND_RX_FIFOFULL, rx_fifofull;				
		jnext	COND_REC_IN_PROGRESS, rx_fifo_overflow;			/* if (SPR_RXE_0x1a & 0x8000) */	
	rx_fifofull:;
		jnzx	0, 15, SPR_RXE_0x1a, 0x000, rx_fifo_overflow;		
		extcond_eoi_only(COND_TX_NAV)
		jnext	COND_FRAME_NEED_ACK, channel_setup;				
		extcond_eoi_only(COND_PHY6);
		jext	COND_TRUE, state_machine_idle;				


/* --------------------------------------------------- HANDLERS ---------------------------------------------------------- */


// ***********************************************************************************************
// HANDLER:	channel_setup
// PURPOSE:	If TBTT expired prepares a beacon transmission else checks FIFO queue for incoming frames.	
//		The condition on SPR_BRC involves
//		COND_NEED_BEACON|COND_NEED_RESPONSEFR|COND_NEED_PROBE_RESP|COND_CONTENTION_PARAM_MODIFIED|COND_MORE_FRAGMENT
//
	channel_setup:;
		call	lr2, bg_noise_sample;					/* Create noise sample */
		jext	COND_MORE_FRAGMENT, skip_beacon_ops;
		jext	COND_TX_TBTTEXPIRE, prepare_beacon_tx;
	skip_beacon_ops:
		extcond_eoi_only(COND_RX_ATIMWINEND);									
		jand	SPR_TXE0_CTL, 0x001, check_tx_data_with_disabled_engine;/* if TX engine was enabled goto check_tx_data */
	check_tx_data:;
		jext	EOI(COND_PHY6), check_tx_data;				
		jnand	0x01F, SPR_BRC, state_machine_idle;			/* No transmission pending */			
		srx	6, 3, SPR_IFS_0x0c, 0x000, GP_REG5;				
		jl	GP_REG5, 0x004, state_machine_start;			/* Something related to IFS time... Maybe we must wait again */
		jext	COND_TRUE, state_machine_idle;

// ***********************************************************************************************
// HANDLER:	prepare_beacon_tx
// PURPOSE:	Prepares parameters (PHY and MAC) needed for a correct Beacon transmission.
//		The condition on SPR_BRC involves
//		COND_NEED_BEACON|COND_NEED_RESPONSEFR|COND_FRAME_BURST|COND_REC_IN_PROGRESS|COND_FRAME_NEED_ACK
//
	prepare_beacon_tx:
		jnand	0x0E3, SPR_BRC, state_machine_idle;
		jnext   0x3D, beacon_tx_param_update;
	        jext    0x3E, beacon_tx_param_update;
	inhibit_sleep_call:;
        	call    lr0, inhibit_sleep_at_tbtt;
	        jext    COND_TRUE, state_machine_idle;
	beacon_tx_param_update:
		jzx	1, 0, SPR_MAC_CMD, 0x000, inhibit_sleep_call;		/* if !(SPR_MAC_Command & (MCMD_BCN0VLD|MCMD_BCN1VLD)), comment this line to send beacon anyway */
		mov	0x001, GP_REG11;
		jext	COND_TRUE, flush_and_stop_tx_engine;
	return_flush_into_prepare_beacon_tx:
		or	[SHM_BEACPHYCTL], 0x000, SPR_TXE0_PHY_CTL; 		/* SPR_TXE0_PHY_CTL = shm_beacon_phy_ctl_word */
		jzx	0, 7, [SHM_HF_MI], 0x000, bcn_no_hw_pwr_ctl;
		mov	SHM_BCNVAL1, SPR_BASE5;
		jne	[SHM_PHYTYPE], 0x000, bcn_no_hw_pwr_ctl;
		mov	SHM_BCNVAL0, SPR_BASE5;	
	bcn_no_hw_pwr_ctl:
		call	lr1, prep_phy_txctl_encoding_already_set;
		mov	TS_BEACON, TX_TYPE_SUBTYPE;
		jext	COND_CONTENTION_PARAM_MODIFIED, skip_parameter_preservation;
		mov	IRQLO_TBTT_INDI, SPR_MAC_IRQLO;
		mov	0, SPR_TSF_Random;
		jext	0x3D, skip_parameter_preservation;
		orx	0, 6, 0x000, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3; 	/* GFR3 = GFR3 & ~0x40 */
		or	SPR_IFS_BKOFFDELAY, 0x000, NEXT_IFS;
		or	CUR_CONTENTION_WIN, 0x000, NEXT_CONTENTION_WIN;	
	        jzx     0, 0, SPR_TSF_0x0e, 0x000, skip_brc_update;
        	orx     0, 10, 0x000, SPR_BRC, SPR_BRC; 			/* SPR_BRC = SPR_BRC & ~TX_MULTICAST_FRAME */
        	orx     0, 2, 0x001, 0x000, SPR_MAC_CMD; 			/* Directed frame queue valid */
	skip_brc_update:
        	orx     14, 1, MIN_CONTENTION_WIN, 0x001, GP_REG5;
        	and     SPR_TSF_Random, GP_REG5, SPR_IFS_BKOFFDELAY;
	skip_parameter_preservation:
        	or      [SHM_BTSFOFF], 0x000, SPR_TSF_0x3a;
        	orx     2, 0, 0x001, SPR_BRC, SPR_BRC; 				/* SPR_BRC = NEED_BEACON | (SPR_BRC & ~(NEED_BEACON | NEED_RESPONSEFR | NEED_PROBE_RESP)) */
        	orx     0, 3, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | CONTENTION_PARAM_MODIFIED */
        	jext    0x3D, goto_set_ifs;
        	mov	0x4D95, SPR_TXE0_CTL;
        	jext    COND_TRUE, state_machine_idle;
	goto_set_ifs:
        	mov	0x4D95, NEXT_TXE0_CTL; 
        	jext    COND_TRUE, set_ifs;

// ***********************************************************************************************
// HANDLER:	check_tx_data
// PURPOSE:	Checks if there is a frame into the FIFO queue. If a frame is incoming from host loads BCM
//		header into SHM and analyzes frame properties, then prepares PHY and MAC parameters for transmission.
//		This code should be invoke with TX engine disabled.
//		The condition on SPR_BRC involves
//		COND_NEED_BEACON|COND_NEED_RESPONSEFR|COND_NEED_PROBE_RESP|COND_CONTENTION_PARAM_MODIFIED|COND_FRAME_BURST
//
	check_tx_data_with_disabled_engine:;			
		extcond_eoi_only(COND_PHY6);		
		orx	1, 8, 0x003, 0x000, SPR_RXE_FIFOCTL0;			/* SPR_Receive_FIFO_Control = 0x300 */
		jnand	0x02F, SPR_BRC, state_machine_idle;			/* if (0x2f & SPR_BRC) goto state_machine_idle */
		jext	COND_TX_NOW, state_machine_start;	
		jnext   0x3E, ready_for_header_copy;
	goon_with_frame_analysis:;
		jnext   COND_TX_MULTICAST_FRAME, ready_for_header_copy;
		jnzx    0, 4, [SHM_HF_MI], 0x000, state_machine_start;
		jne     [SHM_MCASTCOOKIE], 0xFFFF, state_machine_start;
		jext	0x3D, skip_slow_clock_control;						/* check for slow clock control */
		jzx	0, 2, SPR_MAC_CMD, 0x000, slow_clock_control;
	skip_slow_clock_control:;
		orx	0, 10, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~TX_MULTICAST_FRAME */
	ready_for_header_copy:;
		jzx     0, 2, SPR_MAC_CMD, 0x000, slow_clock_control;
		jext	COND_MORE_FRAGMENT, copy_header_into_shm;						
		call	lr0, update_wme_params_availability;
		orx	0, 14, 0x000, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* This was the only edcf_swap_something operation */				
		jne	[SHM_FIFO_RDY], 0x000, fifo_ready_for_tx;		/* if (SHM_FIFO_RDY != 0) */							
		jext	COND_TRUE, slow_clock_control;				
	fifo_ready_for_tx:;
		mov     0x0100, [SHM_TXFCUR];					/* SHM_TXFCUR = 0x0100 */
	copy_header_into_shm:;
		call	lr3, load_tx_header_into_shm;				
		jzx	0, 13, [TXHDR_MACLO,off0], 0x000, check_tx_channel;	/* if !(tx_info.plcp & 2000) */	
		sub.	[TXHDR_TOLO,off0], SPR_TSF_WORD0, GP_REG5;		/* GP_REG5 = tx_info.tstamp_lo - SPR_TSF_word_0 [set carry] */		
		subc	[TXHDR_TOHI,off0], SPR_TSF_WORD1, GP_REG6;		/* GP_REG6 = tx_info.tstamp_hi - SPR_TSF_word_1 - carry */
		jges	GP_REG6, 0x000, check_tx_channel;			/* if (GP_REG6 >=s 0x00) */
		orx	2, 2, 0x005, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = SUPP_EXPIRED | (tx_info.tx_status & ~SUPPRESS_MASK) */
		jext	COND_TRUE, suppress_this_frame;				
	check_tx_channel:;
		srx	1, 7, [TXHDR_MACLO,off0], 0x000, GP_REG5;		/* GP_REG5 = ((tx_info.MAC_ctl_lo) >> 7) & 0x03 */
		srx	7, 8, [TXHDR_EFT,off0], 0x000, GP_REG6;			/* GP_REG6 = ((tx_info.xtra_frame_types) >> 8) & 0xff */
		orx	1, 8, GP_REG5, GP_REG6, GP_REG5;			/* GP_REG5 = (((GP_REG5<<8) | (GP_REG5>>8)) & 0x300) | (GP_REG6 & ~0x300) */
		je	GP_REG5, [SHM_CHAN], check_pmq_tx_header_info;		/* if (GP_REG5 == SHM_CHAN) */
		orx	2, 2, 0x004, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = SUPP_CHAN_MISMATCH | (tx_info.tx_status & ~SUPPRESS_MASK) */
		jext	COND_TRUE, suppress_this_frame;			
	check_pmq_tx_header_info:;
		or	[TXHDR_PHYCTL,off0], 0x000, SPR_TXE0_PHY_CTL;		/* SPR_TXE0_PHY_CTL = tx_info.phy_ctl */
		orx	1, 1, 0x002, [TXHDR_HK5,off0], [TXHDR_HK5,off0];	/* tx_info.housekeeping5 := 0x4 | (tx_info.housekeeping5 & ~0x6) */
		jext	COND_MORE_FRAGMENT, extract_phy_info;						
		or	[TXHDR_FES,off0], 0x000, SPR_TX_FES_Time;		/* SPR_TX_FES_Time := tx_info.fes_time */
		jzx	0, 4, [TXHDR_HK5,off0], 0x000, extract_phy_info;	/* if (!(tx_info.housekeeping5 & USE_FALLBACK)) */
		or	[TXHDR_FESFB,off0], 0x000, SPR_TX_FES_Time;		/* SPR_TX_FES_Time := tx_info.fes_time_fb */					
	extract_phy_info:;
		jnzx	0, 4, [TXHDR_HK5,off0], 0x000, extract_fallback_info;	/* if (tx_info.housekeeping5 & USE_FALLBACK) */	
		srx	7, 0, [TXHDR_PHYRATES,off0], 0x000, GP_REG0;		/* GP_REG0 = (tx_info.phy_rates) & 0xff */
		srx	1, 0, [TXHDR_PHYCTL,off0], 0x000, GP_REG1;		/* GP_REG1 = (tx_info.phy_ctl) & 0x3 */
		jext	COND_TRUE, extract_tx_type_subtype;						
	extract_fallback_info:;
		srx	7, 0, [TXHDR_PLCPFB0,off0], 0x000, GP_REG0;		/* GP_REG0 = (tx_info.plcp_fb0) & 0xff */	
		srx	1, 0, [TXHDR_EFT,off0], 0x000, GP_REG1;			/* GP_REG1 = (tx_info.xtra_frame_types) & 0x3 */
	extract_tx_type_subtype:;
		srx	5, 2, [TXHDR_FCTL,off0], 0x000, TX_TYPE_SUBTYPE;	/* TX_TYPE_SUBTYPE = ((tx_info.fctl) >> 2) & 0x3f */
		call	lr0, get_ptr_from_rate_table;				
		jzx	0, 7, [SHM_HF_MI], 0x000, check_tx_no_hw_pwr_ctl;	/* if !(SHM_HF_MI & MHF_HWPWRCTL) */
		or	SPR_BASE3, 0x000, SPR_BASE5;				
	check_tx_no_hw_pwr_ctl:;
		call	lr1, prep_phy_txctl_with_encoding;			
		srx	0, 4, SPR_TXE0_PHY_CTL, 0x000, GP_REG1;			/* GP_REG1 = (SPR_TXE0_PHY_CTL >> 4) & 0x01 */
		orx	0, 4, GP_REG1, [SHM_CURMOD], GP_REG1;			/* GP_REG1 = ((GP_REG1 << 4) & 0x10) | ([SHM_CURMOD] & ~0x10) -- ([SHM_CURMOD] == 0 ? CCK : OFDM) */
		call	lr0, get_rate_table_duration;				
		add	GP_REG5, [SHM_SLOTT], GP_REG5;					
		orx	11, 3, GP_REG5, 0x000, SPR_TXE0_TIMEOUT;		/* SPR_TXE0_TIMEOUT = ((GP_REG5<<3) | (GP_REG5>>13)) & 0x7ff8 */				
		jnext	COND_MORE_FRAGMENT, check_tx_next_txe_ctl_1;						
		mov	0x4001, SPR_TXE0_CTL;					/* Generate FCS and enable TX engine */
		jext	COND_TRUE, state_machine_idle;				
	check_tx_next_txe_ctl_1:;
		mov	0x4C1D, NEXT_TXE0_CTL;				
		jne	TX_TYPE_SUBTYPE, TS_PROBE_RESP, check_tx_next_txe_ctl_2;	/* if (tx_frame_type_subtype != TS_PROBE_RESP) */					
		mov	0x4D1D, NEXT_TXE0_CTL;					
	check_tx_next_txe_ctl_2:;
		jne	TX_TYPE_SUBTYPE, TS_ATIM, check_tx_txe_ctl_edcf;	/* if (tx_frame_type_subtype != TS_ATIM) */		
		mov	0x6E1D, NEXT_TXE0_CTL;				
	check_tx_txe_ctl_edcf:;
		jzx	0, 8, [SHM_HF_LO], 0x000, end_check_tx_data;		/* if (!(SHM_HF_LO & MHF_EDCF)) */				
		call	lr0, mod_txe0_control_for_edcf;				
	end_check_tx_data:;
		jext	COND_TRUE, set_ifs;						

// ***********************************************************************************************
// HANDLER:	suppress_this_frame
// PURPOSE:	Flushes frame and tells the host that transmission failed.
//
	suppress_this_frame:;
		mov	0, SPR_TXE0_SELECT;					/* SPR_TXE0_SELECT = 0x0000 */			
		jext	COND_TRUE, report_tx_status_to_host;			

// ***********************************************************************************************
// HANDLER:	set_ifs
// PURPOSE:	Prepares backoff time (if it is equal to zero) for the next contention stage.
// 
	set_ifs:;
		extcond_eoi_only(COND_RX_ATIMWINEND);
		or	NEXT_TXE0_CTL, 0x000, SPR_TXE0_CTL;			/* SPR_TXE0_CTL = NEXT_TXE0_CTL */	
		jne	SPR_IFS_BKOFFDELAY, 0x000, state_machine_idle;		/* if (SPR_IFS_BKOFFDELAY != 0) */
		call	lr1, set_backoff_time;					
		jext	COND_TRUE, state_machine_idle;				

// ***********************************************************************************************
// HANDLER:	tx_frame_now
// PURPOSE:	Performs a data, ACK or Beacon frame transmission according to the PHY and MAC parameters that have been set.
//
	tx_frame_now:;
		orx	7, 8, 0x000, 0x004, SPR_RXE_FIFOCTL1;			/* SPR_RXE_FIFOCTL1 = 0x0004 */
		nand	SPR_BRC, 0x180, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~(TX_ERROR | FRAME_NEED_ACK) */
		mov	0x8300, SPR_WEP_CTL;					/* Disable hardwarecrypto */			
		jzx	0, 8, [SHM_HF_LO], 0x000, no_param_update_needed;	/* if (!(SHM_HF_LO & MHF_EDCF)) */			
		jext	0x28, check_for_param_update;						
		je	[0x00,off4], 0x000, check_for_param_update;		/* if (mem[offs4 + 0x0] == 0x00) */
		jnzx	0, 9, GLOBAL_FLAGS_REG1, 0x000, check_for_param_update;	/* if (GLOBAL_FLAGS_REG1 & 0x200) */		
		or	SPR_TSF_0x42, 0x000, SPR_TSF_0x24;			/* SPR_TSF_0x24 = SPR_TSF_0x42 */
		or	SHM_EDCFQCUR, 0x000, SPR_BASE4;				/* SPR_BASE4 = shm_edcf1_paramptr */
		or	[SHM_EDCFQ_TXOP,off4], 0x000, SPR_TSF_0x2a;		/* SPR_TSF_0x2a = mem[offs4 + 0x0] -- copy TXOP value into register */
		orx	0, 9, 0x000, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 & ~0x200 */				
	check_for_param_update:;
		jnzx	0, 0, SPR_IFS_STAT, 0x000, no_param_update_needed;	/* if (SPR_IFS_stat & 0x01) */
		je	SPR_IFS_0x0e, 0x000, no_param_update_needed;		/* if no time was elapsed jump (we don't need param update) */		
		jext	COND_MORE_FRAGMENT, no_param_update_needed;						
		mov	0x0001, GP_REG6;				
		call	lr0, update_wme_params;					
	no_param_update_needed:;
		orx	0, 5, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | FRAME_BURST */					
		orx	0, 4, 0x001, SPR_IFS_CTL, SPR_IFS_CTL;			/* SPR_IFS_CTL = SPR_IFS_CTL | 0x10 */
		orx	1, 1, 0x000, SPR_BRWK0, SPR_BRWK0;			/* SPR_BRWK_0 = SPR_BRWK_0 & ~0x6 */
		mov	0, SPR_TXE0_WM0;					/* Clear register for template ram byte selection */
		mov	0, SPR_TXE0_WM1;					/* Clear register for template ram byte selection */
		jnext	COND_NEED_RESPONSEFR, tx_beacon_or_data;		/* If someone need a response send it, otherwise being tx-ting a beacon or data */
		mov	0x00FF, SPR_TXE0_WM0;					/* Encode the response (an ack here) */
		srx	0, 5, GLOBAL_FLAGS_REG3, 0x000, GP_REG5;		/* GP_REG5 = ((GLOBAL_FLAGS_REG3) >> 5) & 0x1 */					
		orx	0, 12, GP_REG5, SPR_TME_VAL6, SPR_TME_VAL6;		/* SPR_TME_VAL6 = (((GP_REG5<<12) | (GP_REG5>>4)) & 0x1000) | (SPR_TME_VAL6 & ~0x1000) */
		mov	0, SPR_TXE0_SELECT;			
		mov	0, SPR_TXE0_Template_TX_Pointer;	
		mov	0x0010, SPR_TXE0_TX_COUNT;				/* 16 bytes = ack (10) + plcp (6) */
		mov	0x0826, SPR_TXE0_SELECT;				/* select "TX_Count" bytes from template ram, put into serializer and generate EOF */		
		jext	COND_TRUE, complete_tx;	

	tx_beacon_or_data:;
		jnext	COND_NEED_BEACON, tx_data;
		orx     0, 3, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~CONTENTION_PARAM_MODIFIED */
		orx     0, 14, 0x001, SPR_TXE0_WM0, SPR_TXE0_WM0;
		add     SEQUENCE_CTR, 0x001, SEQUENCE_CTR;
		orx     11, 4, SEQUENCE_CTR, 0x000, SPR_TME_VAL28;
		jnext   0x3D, tx_beacon;
		jnzx    0, 7, GLOBAL_FLAGS_REG3, 0x000, set_low_tmpl_addr;	/* if (GLOBAL_FLAGS_REG3 & BEACON_TMPL_LOW) */ 
		mov	0x046A, GP_REG5;
		jext    COND_TRUE, load_beacon_tim;
	set_low_tmpl_addr:
		mov	0x006A, GP_REG5;
	load_beacon_tim:
		add     GP_REG5, [SHM_TIMBPOS], GP_REG5;
		mov	SHM_BEACON_TIM_PTR, SPR_BASE5;
		sl	SPR_BASE5, 0x001, SPR_TXE0_TX_SHM_ADDR;
		mov	0, SPR_TXE0_SELECT;
		orx     1, 0, 0x000, GP_REG5, SPR_TXE0_Template_TX_Pointer;
		mov	0x0008, SPR_TXE0_TX_COUNT;
		mov     0x0805, SPR_TXE0_SELECT;
	wait_tx_bcn_free:;
		jnext   COND_TX_BUSY, wait_tx_bcn_free;
	wait_tx_bcn_write:;
		jext    COND_TX_BUSY, wait_tx_bcn_write;
		sub     CURRENT_DTIM_COUNT, 0x001, CURRENT_DTIM_COUNT;
		mov	0, GP_REG6;
		jgs     CURRENT_DTIM_COUNT, 0x000, not_a_dtim;
		mov	0, CURRENT_DTIM_COUNT;
		srx     0, 4, SPR_TXE0_FIFO_RDY, 0x000, GP_REG6;		/* GP_REG6 = ((SPR_TXE0_FIFO_RDY) >> 4) & 0x1 -- multicast queue */
		orx     0, 10, GP_REG6, SPR_BRC, SPR_BRC;			/* SPR_BRC = (((GP_REG6<<10) | (GP_REG6>>6)) & TX_MULTICAST_FRAME) | (SPR_BRC & ~TX_MULTICAST_FRAME) */
	not_a_dtim:;
		jnand   GP_REG5, 0x002, dtim_offs2;
		jnand   GP_REG5, 0x001, dtim_offs1;
		orx     7, 0, CURRENT_DTIM_COUNT, [0x00,off5], [0x00,off5];
		orx     0, 0, GP_REG6, [0x01,off5], [0x01,off5];
		jext    COND_TRUE, end_dtim_update;
	dtim_offs1:;
		orx     7, 8, CURRENT_DTIM_COUNT, [0x00,off5], [0x00,off5];
		orx     0, 8, GP_REG6, [0x01,off5], [0x01,off5];
		jext    COND_TRUE, end_dtim_update;
	dtim_offs2:;
		jnand   GP_REG5, 0x001, dtim_offs3;
		orx     7, 0, CURRENT_DTIM_COUNT, [0x01,off5], [0x01,off5];
		orx     0, 0, GP_REG6, [0x02,off5], [0x02,off5];
		jext    COND_TRUE, end_dtim_update;
	dtim_offs3:;
		orx     7, 8, CURRENT_DTIM_COUNT, [0x01,off5], [0x01,off5];
		orx     0, 8, GP_REG6, [0x02,off5], [0x02,off5];
	end_dtim_update:;
		orx     1, 0, 0x000, GP_REG5, SPR_TXE0_Template_Pointer;
		or      [0x00,off5], 0x000, SPR_TXE0_Template_Data_Low;
		or      [0x01,off5], 0x000, SPR_TXE0_Template_Data_High;
	wait_tmpl_ram:;
        	jnzx    0, 0, SPR_TXE0_Template_Pointer, 0x000, wait_tmpl_ram;
		add     SPR_TXE0_Template_Pointer, 0x004, SPR_TXE0_Template_Pointer;
		or      [0x02,off5], 0x000, SPR_TXE0_Template_Data_Low;
		or      [0x03,off5], 0x000, SPR_TXE0_Template_Data_High;
		jg      CURRENT_DTIM_COUNT, 0x000, tx_beacon;
		or      [SHM_DTIMPER], 0x000, CURRENT_DTIM_COUNT;
	tx_beacon:;
		mov	0, SPR_TXE0_SELECT;
		mov	0x0068, SPR_TXE0_Template_TX_Pointer;
		or      [SHM_BTL0], 0x000, SPR_TXE0_TX_COUNT;
		jnzx    0, 7, GLOBAL_FLAGS_REG3, 0x000, bcn_tmpl_off1;		/* if (GLOBAL_FLAGS_REG3 & BEACON_TMPL_LOW) */
		mov	0x0468, SPR_TXE0_Template_TX_Pointer;
		or      [SHM_BTL1], 0x000, SPR_TXE0_TX_COUNT;
	bcn_tmpl_off1:
		mov	0x0826, SPR_TXE0_SELECT;
		orx     0, 6, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;
		extcond_eoi_only(COND_TX_TBTTEXPIRE);
		orx     0, 1, 0x001, SPR_TXE0_AUX, SPR_TXE0_AUX;
		jext    0x3D, no_params_preservation;
		jnzx    0, 0, SPR_TSF_0x0e, 0x000, params_restored;
		or      NEXT_IFS, 0x000, SPR_IFS_BKOFFDELAY;
		mov	0, NEXT_IFS;
		or      NEXT_CONTENTION_WIN, 0x000, CUR_CONTENTION_WIN;
		or      MIN_CONTENTION_WIN, 0x000, NEXT_CONTENTION_WIN;
		jext    COND_TRUE, params_restored;
	no_params_preservation:
		or      MIN_CONTENTION_WIN, 0x000, CUR_CONTENTION_WIN;
		jnzx    0, 0, SPR_TSF_0x0e, 0x000, params_restored;
		and     SPR_TSF_Random, CUR_CONTENTION_WIN, SPR_IFS_BKOFFDELAY;
	params_restored:
		mov	IRQLO_BEACON_TX_OK, SPR_MAC_IRQLO;
	complete_tx:
		orx	0, 8, 0x001, 0x000, SPR_WEP_CTL;			/* SPR_WEP_CTL = 0x100 */	
		jext	COND_NEED_BEACON, update_txe_timeout;
		jzx	0, 12, GLOBAL_FLAGS_REG1, 0x000, update_txe_timeout;	/* Am I coming from discard_frame? If I'm not goto update_txe_timeout */				
		mov	0, SPR_TXE0_CTL;					/* Disable tx engine (?) */
		jext	COND_TRUE, pending_tx_resolved;					
	
	tx_data:;
		srx	0, 6, [TXHDR_MACLO,off0], 0x000, GP_REG5;		/* GP_REG5 = ((tx_info.MAC_ctl_lo) >> 6) & 0x1 -- Set FCS calculation bit */			
		xor	GP_REG5, 0x001, GP_REG5;					
		orx	0, 14, GP_REG5, SPR_TXE0_CTL, SPR_TXE0_CTL;		/* SPR_TXE0_Control = (((GP_REG5<<14) | (GP_REG5>>2)) & 0x4000) | (SPR_TXE0_Control & ~0x4000) -- set FCS calculation on TXE0 control (if there is already an FCS we don't need it, else we must compute it (xor on GP_REG5)) */						
		jzx	0, 4, [TXHDR_HK5,off0], 0x000, no_fallback_updates;	/* if (!(tx_info.housekeeping5 & USE_FALLBACK)) */
		or	[TXHDR_PLCPFB0,off0], 0x000, SPR_TME_VAL0;		/* SPR_TME_VAL0 = tx_info.plcp_fb0 */
		or	[TXHDR_PLCPFB1,off0], 0x000, SPR_TME_VAL2;		/* SPR_TME_VAL1 = tx_info.plcp_fb1 */
		or	[TXHDR_DURFB,off0], 0x000, SPR_TME_VAL8;		/* SPR_TME_VAL8 = tx_info.dur_fb */
		or	SPR_TXE0_WM0, 0x013, SPR_TXE0_WM0;			/* SPR_TXE0_WM_0 = SPR_TXE0_WM_0 | 0x13 */
	no_fallback_updates:;				
		orx	0, 14, 0x001, [SHM_TXFCUR], SPR_TXE0_FIFO_CMD;		/* SPR_TXE0_FIFO_CMD = SHM_TXFCUR | 0x4000 */	
		or	[SHM_TXFCUR], 0x000, SPR_TXE0_SELECT;			/* SPR_TXE0_SELECT = SHM_TXFCUR */
		mov	0x0068, SPR_TXE0_TX_COUNT;			
		or	[SHM_TXFCUR], 0x007, SPR_TXE0_SELECT;			/* SPR_TXE0_SELECT = SHM_TXFCUR | 0x07 */
		orx	1, 0, 0x002, [SHM_TXFCUR], SPR_TXE0_SELECT;		/* SPR_TXE0_SELECT = 0x2 | (SHM_TXFCUR & ~0x3) -- Maybe from FIFO in SHM_TXFCUR to serializer, copy X bytes that you read somewhere (PLCP?) and generate EOF */
		srx	1, 0, TX_TYPE_SUBTYPE, 0x000, GP_REG5;			/* GP_REG5 = (TX_TYPE_SUBTYPE) & 0x3 */
		je	GP_REG5, 0x001, dont_update_seq_ctr_value_for_control_frame;	/* If it is a control frame goto dont_update_seq_ctr_value_for_control_frame: control frame doesn't need sequence control */			
		jnzx	3, 12, [TXHDR_STAT,off0], 0x000, update_seq_ctr_value;	/* if (tx_info.tx_status & 0xf000) goto update_seq_ctr_value -- If it is a retransmission don't increase SEQ NUM */
		jzx	0, 3, [TXHDR_MACLO,off0], 0x000, update_seq_ctr_value;	/* if (!(tx_info.MAC_ctl_lo & TX_CTL_START_MSDU)) goto update_seq_ctr_value -- Fragment of the same frame */
		add	SEQUENCE_CTR, 0x001, SEQUENCE_CTR;						
		srx	11, 0, SEQUENCE_CTR, 0x000, [TXHDR_RTSSEQCTR,off0];	/* tx_info.used_seqno = (sequence_ctr) & 0xfff */	
	update_seq_ctr_value:;
		orx	11, 4, [TXHDR_RTSSEQCTR,off0], 0x000, SPR_TME_VAL28;	/* SPR_SPR_TXE_Template_Val_seq = ((tx_info.used_seqno<<4) | (tx_info.used_seqno>>12)) & 0xfff0 */	
		orx	0, 14, 0x001, SPR_TXE0_WM0, SPR_TXE0_WM0;		/* SPR_TXE0_WM0 = SPR_TXE0_WM0 | 0x4000 */
	dont_update_seq_ctr_value_for_control_frame:;
		srx	0, 9, SPR_MAC_CTLHI, 0x000, GP_REG5;			/* GP_REG5 = ((SPR_MAC_Control_High) >> 9) & 0x1 */
		orx	0, 5, GP_REG5, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;	/* GLOBAL_FLAGS_REG3 = (((GP_REG5<<5) | (GP_REG5>>11)) & 0x20) | (GLOBAL_FLAGS_REG3 & ~0x20) */				
		jext	0x3D, tx_frame_update_status_info;						
		mov	0, GP_REG5;				
	tx_frame_update_status_info:;
		orx	0, 7, GP_REG5, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = (((GP_REG5<<7) | (GP_REG5>>9)) & 0x80) | (tx_info.tx_status & ~0x80) */
		orx	0, 12, GP_REG5, 0x000, SPR_TME_VAL6;			/* SPR_SPR_TXE_Template_Val_fc = ((GP_REG5<<12) | (GP_REG5>>4)) & 0x1000 */
		orx	0, 12, 0x001, 0x000, SPR_TME_MASK6;			/* SPR_SPR_TXE_Template_Mask_fc = 0x1000 */
		orx	0, 3, 0x001, SPR_TXE0_WM0, SPR_TXE0_WM0;		/* SPR_TXE0_WM_0 = SPR_TXE0_WM_0 | 0x8 */
		srx	1, 0, TX_TYPE_SUBTYPE, 0x000, GP_REG5;			/* GP_REG5 = (tx_frame_type_subtype) & 0x3 */
		je	GP_REG5, 0x001, tx_frame_analysis;			/* If it is a control frame goto tx_frame_analysis */
		jzx	3, 12, [TXHDR_STAT,off0], 0x000, update_gpreg5_with_cur_fifo;	/* if !(tx_info.tx_status & 0xf000) */
		jzx	0, 8, [SHM_HF_LO], 0x000, set_cf_ack;			/* if !(SHM_HF_LO & MHF_EDCF) */
		or	SHM_EDCFQCUR, 0x000, SPR_BASE4;				/* offs4 = shm_edcf1_paramptr */
		jzx	0, 9, [SHM_EDCFQ_STATUS,off4], 0x000, update_gpreg5_with_cur_fifo;	/* if !(mem[offs4 + 0x7] & 0x200) */
	set_cf_ack:;
		orx	0, 11, 0x001, SPR_TME_VAL6, SPR_TME_VAL6;		/* This sets the CF-Ack for the frame that is going to be send */
		orx	0, 11, 0x001, SPR_TME_MASK6, SPR_TME_MASK6;		
	update_gpreg5_with_cur_fifo:;
		srx	2, 8, [SHM_TXFCUR], 0x000, GP_REG5;			/* GP_REG5 = ((SHM_TXFCUR) >> 8) & 0x7 */
	tx_frame_analysis:;
		orx	0, 8, 0x001, 0x000, SPR_WEP_CTL;			/* SPR_WEP_CTL = 0x100 */
		jext	0x3D, find_tx_frame_type;						
		jnext	0x71, find_tx_frame_type;						
		jne	TX_TYPE_SUBTYPE, 0x024, find_tx_frame_type;		/* if (TX_TYPE_SUBTYPE != TS_ATIM) */
		orx	0, 6, 0x000, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;	/* GLOBAL_FLAGS_REG3 = GLOBAL_FLAGS_REG3 & ~0x40 */
		jzx	0, 0, [TXHDR_RA,off0], 0x000, find_tx_frame_type;	/* if !(tx_info.RA0 & 0x01) -- If it is not a multicast frame goto find_tx_frame_type*/
		orx	0, 10, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | TX_MULTICAST_FRAME */
	find_tx_frame_type:;
		mov	0, SPR_TSF_Random;							
		or	SPR_TSF_0x40, 0x000, [TXHDR_RTSPLCP,off0];		/* tx_info.housekeeping0 = SPR_TSF_0x40 */	
		mov	0, EXPECTED_CTL_RESPONSE;				/* expected_control_response = TS_ASSOC_REQ */		
		je	TX_TYPE_SUBTYPE, TS_RTS, compute_expected_response;				
		jzx	0, 0, [TXHDR_MACLO,off0], 0x000, reset_cur_contention_window;	/* if !(tx_info.MAC_ctl_lo & TX_CTL_IMMED_ACK) */
	compute_expected_response:;
		orx	0, 7, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | FRAME_NEED_ACK */
		or	SPR_BRC, 0x000, 0x000;					/* 0x00 = SPR_BRC */
		mov	TS_CTS, EXPECTED_CTL_RESPONSE;				
		je	TX_TYPE_SUBTYPE, TS_RTS, update_txe_timeout;					
		mov	TS_ACK, EXPECTED_CTL_RESPONSE;				
		jext	COND_TRUE, update_txe_timeout;					
	reset_cur_contention_window:;
		or	MIN_CONTENTION_WIN, 0x000, CUR_CONTENTION_WIN;						
		jnzx	0, 8, [SHM_HF_LO], 0x000, tx_frame_backoff_update_not_needed;		/* if ((SHM_HF_LO >> 8) & 1) != 0) */
		call	lr1, set_backoff_time;					
	tx_frame_backoff_update_not_needed:;
		mov	0, SHORT_RETRIES;				
		mov	0, LONG_RETRIES;				
	update_txe_timeout:;
		jnext	COND_FRAME_NEED_ACK, dont_update_txe_timeout;			
		orx	0, 15, 0x001, SPR_TXE0_TIMEOUT, SPR_TXE0_TIMEOUT;		/* SPR_TXE0_TIMEOUT = SPR_TXE0_TIMEOUT | 0x8000 */	
		jzx     0, 1, GLOBAL_FLAGS_REG2, 0x000, dont_update_txe_timeout;	/* if (!(GLOBAL_FLAGS_REG2 & 0x02)) */
        	orx     7, 8, 0x080, 0x001, SPR_TXE0_TIMEOUT;
	dont_update_txe_timeout:;
		jzx	0, 13, [SHM_HF_LO], 0x000, no_radar_war;			/* if !(SHM_HF_LO & MHF_RADARWAR) */
		mov	0x00C8, GP_REG5;						/* GP_REG5 = APHY_RADAR_THRESH1 */	
		mov	0x03D8, GP_REG6;				
		call	lr0, write_phy_reg;					
	no_radar_war:;
		jne	[SHM_PHYTYPE], 0x001, tx_frame_no_B_phy;		/* if (shm_phy_type != PHY_TYPE_B) */
		jl	[SHM_PHYVER], 0x002, state_machine_idle;		/* if (shm_phy_ver <u 0x02) */
	tx_frame_no_B_phy:;
		je	[SHM_PHYTYPE], 0x000, tx_frame_A_phy;			/* if (shm_phy_type == PHY_TYPE_A) */
		jnzx	1, 0, SPR_TXE0_PHY_CTL, 0x000, tx_frame_A_phy;		/* if (SPR_TXE0_PHY_Control & 0x03) */
		add	SPR_TSF_WORD0, 0x028, GP_REG5;				/* GP_REG5 = SPR_TSF_word_0 + 0x28 */
		jext	COND_TRUE, tx_frame_wait_16us;					
	tx_frame_A_phy:;
		add	SPR_TSF_WORD0, 0x010, GP_REG5;				/* GP_REG5 = SPR_TSF_word_0 + 0x10 */
	tx_frame_wait_16us:;
		jext	COND_TX_DONE, state_machine_idle;			/* Wait for the packet to hit the PHY (16us OFDM, 40us CCK) */
		jne	SPR_TSF_WORD0, GP_REG5, tx_frame_wait_16us;		/* if (SPR_TSF_word_0 != GP_REG5) */
		jnzx	0, 0, SPR_TXE0_PHY_CTL, 0x000, aphy_tssi_selection;	/* if (SPR_TXE0_PHY_CTL & 0x01) */
		mov	0x0029, GP_REG5;					/* GP_REG5 = BPHY_TSSI */
		mov	0x002C, SPR_BASE5;					
		jext	COND_TRUE, update_phy_params;					
	aphy_tssi_selection:;
		mov	0x047B, GP_REG5;					/* GP_REG5 = GPHY_TO_APHY_OFF | APHY_TSSI_STAT */
		mov	0x0038, SPR_BASE5;				
	update_phy_params:;
		call	lr0, sel_phy_reg;					
		rr	[0x01,off5], 0x008, [0x01,off5];				/* mem[offs5 + 0x1] = (mem[offs5 + 0x1] >> 0x08) | (mem[offs5 + 0x1] << (16 - 0x08)) */
		srx	7, 8, [0x00,off5], 0x000, GP_REG5;				/* GP_REG5 = ((mem[offs5 + 0x0]) >> 8) & 0xff */
		orx	7, 0, GP_REG5, [0x01,off5], [0x01,off5];			/* mem[offs5 + 0x1] = (GP_REG5 & 0xff) | (mem[offs5 + 0x1] & ~0xff) */
		rr	[0x00,off5], 0x008, [0x00,off5];				/* mem[offs5 + 0x0] = (mem[offs5 + 0x0] >> 0x08) | (mem[offs5 + 0x0] << (16 - 0x08)) */
		orx	7, 0, SPR_Ext_IHR_Data, [0x00,off5], [0x00,off5];		/* mem[offs5 + 0x0] = (SPR_Ext_IHR_Data & 0xff) | (mem[offs5 + 0x0] & ~0xff) */
		jzx	0, 10, GLOBAL_FLAGS_REG1, 0x000, tx_frame_no_cca_in_progress;	/* if (!(GLOBAL_FLAGS_REG1 & CCA_INPROGR))) */
	tx_frame_no_cca_in_progress:;
		jnzx	0, 11, SPR_IFS_STAT, 0x000, state_machine_idle;			/* if (SPR_IFS_stat & 0x800) */
		jge	SPR_NAV_0x04, 0x0A0, state_machine_idle;			/* if (SPR_NAV_0x04 >=u 0xa0) */
		mov	0xFFFF, SPR_NAV_0x04;			
		orx	0, 10, 0x001, 0x05F, GP_REG5;					/* GP_REG5 = GPHY_TO_APHY_OFF | APHY_NUM_PKT_CNT */				
	wait_for_ihr_data_to_clear:;
		call	lr0, sel_phy_reg;					
		and	SPR_Ext_IHR_Data, 0x01F, GP_REG6;				/* GP_REG6 = SPR_Ext_IHR_Data & 0x1f */
		je	GP_REG6, 0x016, wait_for_ihr_data_to_clear;			/* if (GP_REG6 == 0x16) */
		mov	0, SPR_NAV_0x04;			
		jext	COND_TRUE, state_machine_idle;				

// ***********************************************************************************************
// HANDLER:	tx_infos_update
// PURPOSE:	Updates retries informations and looks for transmission error. If sent frame doesn't require ACK, tells the host that transmission was successfully performed.
//
	tx_infos_update:;	
		orx	0, 5, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~FRAME_BURST */		
		mov	0x8700, SPR_WEP_CTL;					/* SPR_WEP_Control = 0x8700 */
		jnzx	0, 10, [TXHDR_FCTL,off0], 0x000, need_ack;		/* if (tx_info.fctl & 0x400) -- more fragment?? */
		orx	0, 4, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~MORE_FRAGMENT */
	need_ack:;
		jext	COND_NEED_RESPONSEFR, need_response_frame;				
		jext	EOI(COND_TX_UNDERFLOW), tx_underflow;			
		jext	EOI(COND_TX_PHYERR), tx_clear_issues;
		jnext	COND_NEED_BEACON, dont_need_beacon;
	need_response_frame:;
		orx	1, 0, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~(COND_NEED_BEACON | COND_NEED_RESPONSEFR) */
		jext	COND_TRUE, state_machine_start;				
	dont_need_beacon:;
		mov	DEFAULT_RETRY_LIMIT, SHORT_RETRY_LIMIT;												
		/* update_retries_info */
		srx	3, 12, [TXHDR_STAT,off0], 0x000, GP_REG3;		/* GP_REG3 = ((tx_info.tx_status) >> 12) & 0xf */	
		add	GP_REG3, 0x001, GP_REG3;				/* GP_REG3 = GP_REG3 + 1 */	
		orx	3, 12, GP_REG3, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = (((GP_REG3<<12) | (GP_REG3>>4)) & 0xf000) | (tx_info.tx_status & ~0xf000) */	
		jext	COND_FRAME_NEED_ACK, state_machine_start;							
		jext	COND_TRUE, report_tx_status_to_host;			

// ***********************************************************************************************
// HANDLER:	tx_end_wait_10us
// PURPOSE:	Doesn't allow noise measurement for 10us after transmission. 
//
	tx_end_wait_10us:;
		jnzx	0, 4, GLOBAL_FLAGS_REG1, 0x000, tx_end_completed;	/* if (GLOBAL_FLAGS_REG1 & 0x10) */		
		orx	0, 4, 0x001, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 | 0x10 */				
		or	SPR_TSF_WORD0, 0x000, [SHM_WAIT10_CLOCK];		/* mem[SHM_WAIT10_CLOCK] = SPR_TSF_word_0 */							
		jzx	0, 6, [SHM_HF_LO], 0x000, tx_end_completed;		/* if !(SHM_HF_LO & MHF_OFDMPWR) */
		orx	0, 9, 0x000, SPR_GPIO_OUTEN, SPR_GPIO_OUTEN;		/* SPR_GPIO_OUTEN = SPR_GPIO_OUTEN & ~0x200 */
	tx_end_completed:;
		sub	SPR_TSF_WORD0, [SHM_WAIT10_CLOCK], GP_REG9;		/* GP_REG9 = SPR_TSF_word_0 - mem[SHM_WAIT10_CLOCK] */
		jl	GP_REG9, 0x008, check_conditions_no_tx;			/* if (GP_REG9 <u 0x08) goto check_conditions_no_tx */
		mov	0x0027, GP_REG5;					/* GP_REG5 = BPHY_JSSI */
		call	lr0, sel_phy_reg;					
		and	SPR_Ext_IHR_Data, 0x0FF, [SHM_PHYTXNOI];		/* shm_phy_noise_after_TX = SPR_Ext_IHR_Data & 0xff */		
		orx	0, 4, 0x000, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 & ~0x10 */				
		jext	EOI(COND_TX_DONE), state_machine_idle;			
		jext	COND_TRUE, report_tx_status_to_host;			

// ***********************************************************************************************
// HANDLER:	report_tx_status_to_host
// PURPOSE:	Reports informations about transmission to the host, informing it about success or failure of the operation.
//
	report_tx_status_to_host:;
		jand	[TXHDR_HK4,off0], 0x003, dont_clear_housekeeping;	/* if !(tx_info.housekeeping4 & 0x03) */			
		extcond_eoi_only(COND_RX_FIFOFULL);
		jext	COND_RX_FIFOBUSY, report_tx_status_to_host;		
		jext	COND_RX_CRYPTBUSY, report_tx_status_to_host;		
		mov	0, [TXHDR_RTS,off0];					/* tx_info.housekeeping3 = 0x0000 */
		jnext	COND_NEED_RTS, remove_frame_from_fifo;				
		orx	0, 6, 0x001, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = tx_info.tx_status | 0x40 */		
		jext	COND_TRUE, rise_status_interrupt;					
	remove_frame_from_fifo:;
		orx	0, 13, 0x001, [SHM_TXFCUR], SPR_TXE0_FIFO_CMD;		/* SPR_TXE0_FIFO_CMD = SHM_TXFCUR | 0x2000 */
		jzx	0, 0, [TXHDR_STAT,off0], 0x000, rise_status_interrupt;	/* if !(tx_info.tx_status & 0x01) */
		or	SPR_RXE_PHYRXSTAT1, 0x000, [TXHDR_RTS,off0];		/* tx_info.housekeeping3 = SPR_RXE_PHYRS_1 */
	rise_status_interrupt:;
		mov	0x0080, SPR_MAC_IRQLO;					/* SPR_MAC_Interrupt_Status_Low = MI_NSPECGEN_0 */			
		jnzx	0, 13, SPR_MAC_CTLHI, 0x000, discard_tx_status;		/* if (SPR_MAC_Control_High & MCTL_DISCARD_TXSTATUS) */
		or	[TXHDR_STAT,off0], 0x000, GP_REG5;			/* GP_REG5 = tx_info.tx_status */
		orx	0, 1, GP_REG5, GP_REG5, GP_REG5;			/* GP_REG5 = (((GP_REG5<<1) | (GP_REG5>>15)) & 0x2) | (GP_REG5 & ~0x2) */
		or	[TXHDR_RTSPHYSTAT,off0], 0x000, SPR_TX_STATUS3;		/* SPR_TX_Status_3 = tx_info.phy_tx_status */
		or	[TXHDR_RTSSEQCTR,off0], 0x000, SPR_TX_STATUS2;		/* SPR_TX_Status_2 = tx_info.used_seqno */
		or	[TXHDR_COOKIE,off0], 0x000, SPR_TX_STATUS1;		/* SPR_TX_Status_1 = tx_info.cookie */
		orx	0, 0, 0x001, GP_REG5, SPR_TX_STATUS0;			/* SPR_TX_Status_0 = GP_REG5 | 0x1 */
	discard_tx_status:;
		jnext	COND_NEED_RTS, dont_clear_tx_retry_info;				
		orx	3, 8, 0x000, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = tx_info.tx_status & ~0xf00 */
		jext	COND_TRUE, dont_clear_housekeeping;					
	dont_clear_tx_retry_info:;
		orx	1, 0, 0x000, [TXHDR_HK4,off0], [TXHDR_HK4,off0];	/* tx_info.housekeeping4 = tx_info.housekeeping4 & ~0x3 */
	dont_clear_housekeeping:;
		orx	0, 6, 0x000, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = tx_info.tx_status & ~0x40 */
		orx	0, 11, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~NEED_RTS */
		mov	0, [TXHDR_RTSPHYSTAT,off0];				/* tx_info.phy_tx_status = 0x0000 */
		jext	COND_TRUE, state_machine_start;				

// ***********************************************************************************************
// HANDLER:	tx_contention_params_update
// PURPOSE:	Updates current window parameter according to success or failure of transmission operation. Checks if retries reached the top limit and eventually commands a drop operation.
//
	tx_contention_params_update:;
		jnext	COND_FRAME_NEED_ACK, finish_updates;					
		jext	COND_REC_IN_PROGRESS, finish_updates;
		jext	COND_FRAME_BURST, finish_updates;											
		orx	0, 7, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~FRAME_NEED_ACK */			
		jnext	EOI(COND_TX_PMQ), reset_antenna_ctr_if_needed;					
		jzx	0, 8, [SHM_HF_LO], 0x000, skip_tsf_update;		/* if !(SHM_HF_LO & MHF_EDCF) */
		mov	0, SPR_TSF_0x24;			
		mov	0, SPR_TSF_0x2a;			
		orx	0, 9, 0x000, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 & ~0x200 */							
	skip_tsf_update:
		jext	COND_TRUE, update_contention_params;	
	reset_antenna_ctr_if_needed:;
		jnext	COND_RX_FCS_GOOD, dont_reset_antenna_ctr;					
		je	RX_TYPE_SUBTYPE, TS_CTS, dont_reset_antenna_ctr;					
		mov	0, ANTENNA_DIVERSITY_CTR;				
	dont_reset_antenna_ctr:;
		jext	COND_TX_ERROR, update_contention_params;						
		jext	EOI(COND_RX_FCS_GOOD), update_params_on_success;				
		je	GPHY_SYM_WAR_FLAG, 0x001, update_params_on_success;					
	update_contention_params:;
		orx	0, 8, 0x000, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC & ~TX_ERROR */				
		call	lr1, antenna_diversity_helper;				
		orx	0, 4, 0x000, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC & ~MORE_FRAGMENT */
		orx	14, 1, CUR_CONTENTION_WIN, 0x001, CUR_CONTENTION_WIN;		/* CUR_CONTENTION_WIN = CUR_CONTENTION_WIN * 2 + 1 */			
		and	CUR_CONTENTION_WIN, MAX_CONTENTION_WIN, CUR_CONTENTION_WIN;	/* CUR_CONTENTION_WIN = CUR_CONTENTION_WIN & MAX_CONTENTION_WIN */					
		je	EXPECTED_CTL_RESPONSE, TS_CTS, using_fallback;					
		jzx	0, 2, [TXHDR_MACLO,off0], 0x000, using_fallback;		/* if !(tx_info.MAC_ctl_lo & TX_CTL_SEND_RTS) */			
		orx	0, 11, 0x001, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC | NEED_RTS */						
	using_fallback:;
		jl	GP_REG3, [SHM_SFFBLIM], dont_use_fallback;			/* if (GP_REG3 <u shm_short_frame_tx_count_fallbackrate_thresh) */
		orx	0, 4, 0x001, [TXHDR_HK5,off0], [TXHDR_HK5,off0];		/* tx_info.housekeeping5 = USE_FALLBACK | (tx_info.housekeeping5 & ~USE_FALLBACK) */
	dont_use_fallback:;
		add	SHORT_RETRIES, 0x001, SHORT_RETRIES;
		jne	SHORT_RETRIES, SHORT_RETRY_LIMIT, short_retry_limit_not_reached_yet;						
		or	MIN_CONTENTION_WIN, 0x000, CUR_CONTENTION_WIN;				/* CUR_CONTENTION_WIN := MIN_CONTENTION_WIN */			
	short_retry_limit_not_reached_yet:;
		jge	GP_REG3, SHORT_RETRY_LIMIT, retry_limit_reached;			/* if (GP_REG3 >=u SHORT_RETRY_LIMIT) */					
		jext	COND_TRUE, retry_limit_not_reached;					
	retry_limit_reached:;
		mov	0, SHORT_RETRIES;
		extcond_eoi_only(COND_TX_PMQ);
		jnzx	0, 8, [SHM_HF_LO], 0x000, backoff_update_not_needed_1;			/* if (SHM_HF_LO & MHF_EDCF) */			
		call	lr1, set_backoff_time;					
	backoff_update_not_needed_1:;
		orx	0, 3, 0x001, [TXHDR_HK5,off0], [TXHDR_HK5,off0];			/* tx_info.housekeeping5 = FAILED | (tx_info.housekeeping5 & ~FAILED) */
		orx	0, 11, 0x000, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC & ~NEED_RTS */
		jext	COND_TRUE, report_tx_status_to_host;				/* We must discard the frame due to short_retry_limit reaching */				
	retry_limit_not_reached:;
		jnzx	0, 8, [SHM_HF_LO], 0x000, finish_updates;			/* if (SHM_HF_LO & MHF_EDCF) */
		call	lr1, set_backoff_time;					
	finish_updates:;
		extcond_eoi_only(COND_TX_PMQ);
		jext	COND_NEED_RTS, report_tx_status_to_host;		
		jext	COND_TRUE, state_machine_start;				
	update_params_on_success:;
		srx	1, 0, TX_TYPE_SUBTYPE, 0x000, GP_REG5;			/* GP_REG5 = (TX_TYPE_SUBTYPE) & 0x3 */		
		je	GP_REG5, 0x001, update_params_control_frame;		/* if frame is a control frame goto update_params_control_frame */
		or	MIN_CONTENTION_WIN, 0x000, CUR_CONTENTION_WIN;						
	update_params_control_frame:;
		jnzx	0, 8, [SHM_HF_LO], 0x000, backoff_update_not_needed_3;		/* if (SHM_HF_LO & MHF_EDCF) */
		call	lr1, set_backoff_time;					
	backoff_update_not_needed_3:;
		mov	0, SHORT_RETRIES;				
		jzx	0, 1, [TXHDR_MACLO,off0], 0x000, dont_update_long_frame_retries;/* if (!(tx_info.MAC_ctl_lo & TX_CTL_LONG_FRAME)) */
		mov	0, LONG_RETRIES;				
	dont_update_long_frame_retries:;
		orx	0, 0, 0x001, [TXHDR_STAT,off0], [TXHDR_STAT,off0];		/* tx_info.tx_status = tx_info.tx_status | 0x1 */
		jext	COND_TRUE, report_tx_status_to_host;			

// ***********************************************************************************************
// HANDLER:	send_response
// PURPOSE:	Sends an ACK back to the station whose MAC was contained in the source address header field.
//		At the end set the NEED_RESPONSEFR bit in SPR_BRC that will trigger the condition COND_NEED_RESPONSEFR
//		that will be evaluated at next tx_frame_now
//		Values are taken from the tables in initvals.asm
//		e.g. for CCK
//		1Mb/s	(A)	off5=37E
//		2Mb/s	(4)	off5=389
//		5.5Mb/s	(7)	off5=394
//		11Mb/s	(E)	off5=39F
//
	send_response:;
		mov	0x000E, GP_REG5;				
		or	[0x01,off2], 0x000, SPR_TME_VAL0;			/* SPR_SPR_TXE_Template_Val_plcp0 = mem[offs2 + 0x1] */
		je	[SHM_CURMOD], 0x000, cck_mod;				/* If we are using cck goto cck_mod */
		orx	10, 5, GP_REG5, [0x01,off2], SPR_TME_VAL0;		/* SPR_SPR_TXE_Template_Val_plcp0 = (((GP_REG5 << 5) | (GP_REG5 >> 11)) & 0xffe0) | (mem[offs2 + 0x1] & ~0xffe0) */
	cck_mod:;								/* Set receiver mac address */
		or	[0x02,off2], 0x000, SPR_TME_VAL2;			/* SPR_SPR_TXE_Template_Val_plcp1 = mem[offs2 + 0x2] */
		mov	0, SPR_TME_VAL4;					/* SPR_SPR_TXE_Template_Val_plcp2 = 0x0000 */
		or	[RX_FRAME_ADDR2_1,off1], 0x000, SPR_TME_VAL10;		/* SPR_SPR_TXE_Template_Val_ra0 = mem[rx_frame_offs + FR_OFFS_ADDR2] */
		mov	0xFFFF, SPR_TME_MASK10;					/* SPR_SPR_TXE_Template_Mask_ra0 = 0xffff */
		or	[RX_FRAME_ADDR2_2,off1], 0x000, SPR_TME_VAL12;		/* SPR_SPR_TXE_Template_Val_ra1 = mem[rx_frame_offs + FR_OFFS_ADDR2 + 1] */
		mov	0xFFFF, SPR_TME_MASK12;					/* SPR_SPR_TXE_Template_Mask_ra1 = 0xffff */
		or	[RX_FRAME_ADDR2_3,off1], 0x000, SPR_TME_VAL14;		/* SPR_SPR_TXE_Template_Val_ra2 = mem[rx_frame_offs + FR_OFFS_ADDR2 + 2] */
		mov	0xFFFF, SPR_TME_MASK14;					/* SPR_SPR_TXE_Template_Mask_ra2 = 0xffff */
		or	[SHM_ACKCTSPHYCTL], 0x000, SPR_TXE0_PHY_CTL;		/* SPR_TXE0_PHY_CTL = SHM_ACKCTSPHYCTL */
		jzx	0, 7, [SHM_HF_MI], 0x000, no_hw_pwr_ctl;		/* if (!(SHM_HF_MI & MHF_HWPWRCTL)) */
		or	SPR_BASE2, 0x000, SPR_BASE5;				
	no_hw_pwr_ctl:;
		srx	1, 0, [SHM_CURMOD], 0x000, GP_REG1;			/* GP_REG1 = modulation (OFDM or CCK) */
		call	lr1, prep_phy_txctl_with_encoding;			
		mov	0xFFFF, SPR_TME_MASK6;			
		mov	0xFFFF, SPR_TME_MASK8;			
		mov	0x00D4, SPR_TME_VAL6;					/* SPR_SPR_TXE_Template_Val_fc = 0x00D4 */			
		mov	TS_ACK, TX_TYPE_SUBTYPE;				
		je	RX_TYPE_SUBTYPE, TS_PSPOLL, pspoll_frame;					
		jnzx	0, 10, [RX_FRAME_FC,off1], 0x000, ctl_more_frag;	/* if (CTL_MORE_FRAG(rx_frame)) */			
		jext	COND_TRUE, pspoll_frame;					
	ctl_more_frag:;
		or	[SHM_CURMOD], 0x000, GP_REG1;				/* GP_REG1 = [SHM_CURMOD] */
		call	lr0, get_rate_table_duration;				
		sub	GP_REG5, [SHM_PREAMBLE_DURATION], GP_REG5;		/* GP_REG5 = GP_REG5 - shm_preamble_duration */
		jgs	GP_REG5, [RX_FRAME_DURATION,off1], pspoll_frame;	/* if (GP_REG5 >s mem[rx_frame_offs + FR_OFFS_DURID]) */
		sub	[RX_FRAME_DURATION,off1], GP_REG5, SPR_TME_VAL8;	/* SPR_SPR_TXE_Template_Val_dur = mem[rx_frame_offs + FR_OFFS_DURID] - GP_REG5 */
		jext	COND_TRUE, trigger_cts_ack_transmission;					
	pspoll_frame:;
		mov	0, SPR_TME_VAL8;					/* SPR_SPR_TXE_Template_Val_dur = 0x0000 */		
		jnext	0x71, trigger_cts_ack_transmission;						
		orx	0, 15, 0x001, SPR_TME_VAL8, SPR_TME_VAL8;		/* SPR_SPR_TXE_Template_Val_dur = SPR_SPR_TXE_Template_Val_dur | 0x8000 */		
	trigger_cts_ack_transmission:;
		orx	2, 0, 0x002, SPR_BRC, SPR_BRC;				/* SPR_BRC = NEED_RESPONSEFR | (SPR_BRC & ~(NEED_BEACON | NEED_RESPONSEFR | NEED_PROBE_RESP)) */
		je	GPHY_SYM_WAR_FLAG, 0x000, sym_war_txe_ctl;					
		mov	0x4001, NEXT_TXE0_CTL;					/* Generate FCS and enable TX engine */
		jext	COND_TRUE, send_response_end;					
	sym_war_txe_ctl:;
		mov	0x4021, NEXT_TXE0_CTL;					/* Generate FCS (4), enable TX engine (1) and 2(??)*/
	send_response_end:;
		je	RX_TYPE_SUBTYPE, TS_RTS, send_control_frame_to_host;			
		jext	COND_RX_COMPLETE, rx_complete;				
		jext	COND_TRUE, state_machine_idle;	

// ***********************************************************************************************
// HANDLER:	tx_timers_setup
// PURPOSE:	Updates timers informations.
//
	tx_timers_setup:;
		jzx	0, 8, SPR_BRPO0, 0x000, proceed_with_timer_update;	/* if (!(SPR_BRPO0 & 0x100)) */
		orx	1, 3, 0x000, GLOBAL_FLAGS_REG2, GLOBAL_FLAGS_REG2;	/* GLOBAL_FLAGS_REG2 = GLOBAL_FLAGS_REG2 & ~0x18 */				
		orx	0, 8, 0x000, SPR_BRPO0, SPR_BRPO0;			/* SPR_BRPO0 = SPR_BRPO0 & ~0x100 */
		jzx	0, 10, GLOBAL_FLAGS_REG1, 0x000, cca_not_in_progress;	/* if !(GLOBAL_FLAGS_REG1 & CCA_INPROGR) */	
	cca_not_in_progress:;
		jzx	0, 8, [SHM_HF_LO], 0x000, no_timers_update_needed;	/* if !(SHM_HF_LO & MHF_EDCF) */
		jzx	0, 0, SPR_IFS_STAT, 0x000, no_timers_update_needed;	/* if !(SPR_IFS_stat & 0x01) */
		je	SPR_IFS_0x0e, 0x000, no_timers_update_needed;		/* if (SPR_IFS_0x0e == 0x00) */
		mov	0, GP_REG6;				
		call	lr0, update_wme_params;					
	no_timers_update_needed:;
		jext	COND_TRUE, state_machine_idle;				
	proceed_with_timer_update:;
		jnzx	0, 11, SPR_IFS_STAT, 0x000, timers_update_goon;		/* if (SPR_IFS_stat & 0x800) */			
		orx	0, 8, 0x001, SPR_BRPO0, SPR_BRPO0;			/* SPR_BRPO0 = SPR_BRPO0 | 0x100 */
		jzx	0, 6, GLOBAL_FLAGS_REG2, 0x000, timers_update_goon;	/* if !(GLOBAL_FLAGS_REG2 & 0x40) */		
	timers_update_goon:;
		jzx	0, 11, [SHM_HF_LO], 0x000, no_ACI;			/* if !(SHM_HF_LO & MHF_ACI) */
		mov	0x048A, GP_REG5;					/* GP_REG5 = GPHY_TO_APHY_OFF | APHY_N1_N2_THRESH */
		call	lr0, sel_phy_reg;					
		orx	2, 12, 0x003, SPR_Ext_IHR_Data, SPR_Ext_IHR_Data;	/* SPR_Ext_IHR_Data = 0x3000 | (SPR_Ext_IHR_Data & ~0x7000) */	
		or	SPR_Ext_IHR_Data, 0x000, GP_REG6;			/* GP_REG6 = SPR_Ext_IHR_Data */
		call	lr0, write_phy_reg;					
	no_ACI:;
		jzx	0, 4, GLOBAL_FLAGS_REG2, 0x000, end_tx_timers_setup;	/* if !(GLOBAL_FLAGS_REG2 & 0x10) */			
		orx	1, 3, 0x001, GLOBAL_FLAGS_REG2, GLOBAL_FLAGS_REG2;	/* GLOBAL_FLAGS_REG2 = 0x8 | (GLOBAL_FLAGS_REG2 & ~0x18) */				
	end_tx_timers_setup:;
		jnzx	0, 7, SPR_RXE_0x1a, 0x000, state_machine_start;		/* if (SPR_RXE_0x1a & 0x80) */
		orx	1, 3, 0x001, GLOBAL_FLAGS_REG2, GLOBAL_FLAGS_REG2;	/* GLOBAL_FLAGS_REG2 = 0x8 | (GLOBAL_FLAGS_REG2 & ~0x18) */				
		jext	COND_TRUE, state_machine_start;				

// ***********************************************************************************************
// HANDLER:	rx_plcp
// PURPOSE:	If header was successfully received, extracts from it frame related informations.
//		Current time is stored inside four registers RX_TIME_WORD[0-3]
//		RX_PHY_ENCODING stores the kind of encoding for all the succeeding analysis: 0 is CCK, 1 is OFDM
//		At the beginning switch off the TX engine if it is not
//
	rx_plcp:;
		jext	EOI(COND_RX_FCS_GOOD), rx_plcp;				
		mov	0, GPHY_SYM_WAR_FLAG;				
		jnzx	0, 2, SPR_RXE_FIFOCTL1, 0x000, state_machine_idle;		/* if (SPR_RXE_FIFOCTL1 & 0x04) -- Air-buffer is being flushed, try later */
		jzx	0, 0, SPR_TXE0_CTL, 0x000, sync_rx_frame_time_with_TSF;		/* if (!(SPR_TXE0_CTL & 0x01)) */
		mov	0, SPR_TXE0_CTL;			
		orx	2, 0, 0x000, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC & ~(NEED_BEACON | NEED_RESPONSEFR | NEED_PROBE_RESP) */
	sync_rx_frame_time_with_TSF:;
		or	SPR_TSF_WORD0, 0x000, RX_TIME_WORD0;				
		or	SPR_TSF_WORD1, 0x000, RX_TIME_WORD1;				
		or	SPR_TSF_WORD2, 0x000, RX_TIME_WORD2;				
		or	SPR_TSF_WORD3, 0x000, RX_TIME_WORD3;				
		jne	RX_TIME_WORD0, SPR_TSF_WORD0, sync_rx_frame_time_with_TSF;								
		srx	0, 13, SPR_RXE_ENCODING, 0x000, RX_PHY_ENCODING;		/* rx_phy_encoding = ((SPR_RXE_0x1c) >> 13) & 0x1 -- can be 0 (CCK) or 1 (OFDM)*/		
		jne	[SHM_PHYTYPE], 0x000, rx_plcp_not_A_phy;			/* if (SHM_PHYTYPE != PHY_TYPE_A) */
		mov	0x01, RX_PHY_ENCODING;						/* RX_PHY_ENCODING = OFDM -- force OFDM for A phy type */		
	rx_plcp_not_A_phy:;
		mov	0x0008, GP_REG5;						/* GP_REG5 = channel */
		call	lr0, sel_phy_reg;						/* read the channel */
		srx	0, 8, [SHM_CHAN], 0x000, GP_REG5;				/* GP_REG5 = (shm_cur_channel >> 8) & 0x01 */
		orx	0, 8, GP_REG5, SPR_Ext_IHR_Data, GP_REG5;			/* GP_REG5 = (((GP_REG5<<8) | (GP_REG5>>8)) & 0x100) | (SPR_Ext_IHR_Data & ~0x100) */
		orx	9, 3, GP_REG5, [SHM_PHYTYPE], [SHM_RXHDR_RXCHAN];		/* rx_hdr.RxChan = (((GP_REG5<<3) | (GP_REG5>>13)) & 0x1ff8 | (shm_phy_type & ~01ff8) -- The channel was passed to the driver? */
		or	SPR_BRC, 0x140, SPR_BRC;					/* SPR_BRC = SPR_BRC | (TX_ERROR | REC_IN_PROGRESS) */
		orx	0, 9, 0x000, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC & ~RX_ERROR */
		orx	0, 0, 0x000, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 = GLOBAL_FLAGS_REG3 & ~RX_FRAME_DISCARD */				
	wait_for_header_to_be_received:;
		jext	COND_RX_COMPLETE, header_received;				/* Go on since rx was complete or frame length is >= 38 bytes (PLCP + MAC Header) */
		jl	SPR_RXE_FRAMELEN, 0x026, wait_for_header_to_be_received;				 
	header_received:;
		mov	0, [SHM_RXHDR_MACST_LOW];					/* rx_hdr.RxStatus1 = 0x0000 */			
		mov	0, [SHM_RXHDR_MACST_HIGH];					/* rx_hdr.RxStatus2 = 0x0000 */
		jl      SPR_RXE_FRAMELEN, 0x010, rx_too_short;				/* Shortest frame must be at least 16 bytes (PLCP + 10 bytes (CTS,ACK)) */ 			
		srx	5, 2, [RX_FRAME_FC,off1], 0x000, RX_TYPE_SUBTYPE;		/* RX_TYPE_SUBTYPE = ((mem[rx_frame_offs + FR_OFFS_CTL]) >> 2) & 0x3f -- Extract Type and subtype*/		
		srx	1, 2, [RX_FRAME_FC,off1], 0x000, RX_TYPE;			/* RX_TYPE = ((mem[rx_frame_offs + FR_OFFS_CTL]) >> 2) & 0x3 -- Extract type*/
		orx	1, 12, 0x000, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 = GLOBAL_FLAGS_REG3 & ~NOT_REGULAR_ACK|QOS_DATA_FRAME */				
		srx	0, 8, [RX_FRAME_FC,off1], 0x000, GP_REG5;			/* GP_REG5 = ((mem[rx_frame_offs + FR_OFFS_CTL]) >> 8) & 0x1 */
		srx	0, 9, [RX_FRAME_FC,off1], 0x000, GP_REG6;			/* GP_REG6 = ((mem[rx_frame_offs + FR_OFFS_CTL]) >> 9) & 0x1 */
		and	GP_REG5, GP_REG6, GP_REG6;					/* GP_REG6 = GP_REG5 & GP_REG6 -- Check if both toDS and fromDS were set */
		orx	0, 11, GP_REG6, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 = (((GP_REG6<<11) | (GP_REG6>>5)) & 0x800) | (GLOBAL_FLAGS_REG3 & ~WDS_FRAME) */				
		and	RX_TYPE_SUBTYPE, 0x023, GP_REG5;				/* GP_REG5 = RX_TYPE_SUBTYPE & 0x23 --  determine if frame is a QoS data frame */	
		jne	GP_REG5, 0x022, not_qos_data;					/* if (GP_REG5 != 0x22) : if (subtype)(type)!=(1xyw)(10) skip qos check */
		xor	GP_REG6, 0x001, GP_REG6;					/* bit 0 == 1 if (qos data+!wds frame)|(other+wds frame) */
		add	SPR_BASE1, 0x00F, SPR_BASE5;					/* SPR_BASE5 = rx_frame_offs + FR_OFFS_DAT -- load offset to access data */
		jzx	0, 11, GLOBAL_FLAGS_REG3, 0x000, rx_plcp_not_wds;		/* if (!(GLOBAL_FLAGS_REG3 & WDS_FRAME))  */	
		add	SPR_BASE5, 0x003, SPR_BASE5;					/* add 6 bytes if wds (in this case we have addr4 present) */
	rx_plcp_not_wds:;
		jzx	1, 5, [0x00,off5], 0x000, not_qos_data;				/* if (!(mem[offs5 + 0x0] & 0x60)) goto not_qos_data -- in case a non regular ack is needed */
		orx	0, 13, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 = NOT_REGULAR_ACK | (GLOBAL_FLAGS_REG3 & ~NOT_REGULAR_ACK) */
	not_qos_data:;
		orx	0, 5, GP_REG6, 0x000, SPR_RXE_FIFOCTL1;				/* SPR_RXE_FIFOCTL1 = ((GP_REG6<<5) | (GP_REG6>>11)) & 0x20 -- maybe we must forward frames if we are a WDS (??), bit 0x20 will be set with strange combination of qos and wds type, e.g., with no qos data and !wds it is cleared */
		jext	COND_RX_RAMATCH, rx_plcp_and_ra_match;				/* If the frame wasn't sent to me update NAV else goto rx_plcp_and_ra_match */
		jnzx	0, 15, [RX_FRAME_DURATION,off1], 0x000, check_frame_version_validity;	/* if (mem[rx_frame_offs + FR_OFFS_DURID] & 0x8000) */
		or	[RX_FRAME_DURATION,off1], 0x000, SPR_NAV_ALLOCATION;		/* SPR_NAV_ALLOCATION = mem[rx_frame_offs + FR_OFFS_DURID] */
		orx	4, 11, 0x002, SPR_NAV_CTL, SPR_NAV_CTL;				/* SPR_NAV_Control = 0x1000 | (SPR_NAV_Control & ~0xf800) */
		jext	COND_TRUE, check_frame_version_validity;					
	rx_plcp_and_ra_match:;
		jzx	0, 4, [SHM_HF_LO], 0x000, check_frame_version_validity;		/* if !(SHM_HF_LO & MHF_BTCOEXIST) */
		orx	0, 8, 0x001, SPR_GPIO_OUT, SPR_GPIO_OUT;			/* SPR_GPIO_OUT = SPR_GPIO_OUT | 0x100 */
	check_frame_version_validity:;
		jzx	1, 0, [RX_FRAME_FC,off1], 0x000, disable_crypto_engine;		/* if (!(mem[rx_frame_offs + FR_OFFS_CTL] & 0x03)) -- We can accept only 802.11 version 0 frames */			
		orx	0, 0, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;	/* GLOBAL_FLAGS_REG3 = RX_FRAME_DISCARD | (GLOBAL_FLAGS_REG3 & ~RX_FRAME_DISCARD) -- This set the bit that allow discard */				
		jext	COND_TRUE, rx_too_short;				
	disable_crypto_engine:;
		mov	0x8300, SPR_WEP_CTL;					/* Disable crypto engine */	
	start_frame_analysis:;
		orx	1, 0, 0x002, SPR_RXE_FIFOCTL1, SPR_RXE_FIFOCTL1;	/* SPR_RXE_FIFOCTL1 = 0x2 | (SPR_RXE_FIFOCTL1 & ~0x3) -- clear bit 0*/	
		srx	7, 0, [RX_FRAME_PLCP_0,off1], 0x000, GP_REG0;		/* GP_REG0 = first PLCP byte */	
		or	RX_PHY_ENCODING, 0x000, GP_REG1;			/* GP_REG1 = RX_PHY_ENCODING */
		call	lr0, get_ptr_from_rate_table;				/* load off2 and off3 according to GP_REG0 and GP_REG1 */
		jne	RX_TYPE, 0x002, rx_plcp_not_data_frame;			/* if (RX_TYPE != 0x02) -- if frame is not a data frame goto rx_plcp_not_data_frame */
		and	RX_TYPE_SUBTYPE, 0x023, GP_REG5;			/* GP_REG5 = RX_TYPE_SUBTYPE & 0x23 -- (x000)(10) -> data, can be qos data */	
		je	GP_REG5, 0x002, rx_data_plus;				/* no qos data */
		je	GP_REG5, 0x022, rx_data_plus;				/* qos data, unfortunately we do not implement yet qos... */
		jext	COND_TRUE, send_response_if_ra_match;			
	rx_plcp_not_data_frame:;						/* If it is not a data frame */
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;			
		jnzx	0, 15, SPR_RXE_0x1a, 0x000, rx_fifo_overflow;		/* if (SPR_RXE_0x1a & 0x8000) */
		jnext	COND_RX_COMPLETE, rx_plcp_not_data_frame;		/* Wait until reception is not complete */
	rx_plcp_wait_RXE_x1a:;
		jzx	0, 14, SPR_RXE_0x1a, 0x000, rx_plcp_wait_RXE_x1a;	/* if (!(SPR_RXE_0x1a & 0x4000)) */			
		srx	0, 5, SPR_RXE_PHYRXSTAT0, 0x000, [SHM_LAST_RX_ANTENNA];	/* shm_last_rx_antenna = ((SPR_RXE_PHYRS_0) >> 5) & 0x1 */
		jg	SPR_RXE_FRAMELEN, [SHM_MAXPDULEN], rx_complete;		/* if (SPR_RXE_RX_Frame_len >u shm_max_mpdu_len) */
		jext	COND_RX_FCS_GOOD, rx_plcp_good_fcs;					
		call	lr1, check_gphy_sym_war;				
		je	GPHY_SYM_WAR_FLAG, 0x000, rx_complete;				
	rx_plcp_good_fcs:;							/* Good FCS */
		jne	RX_TYPE, 0x000, rx_plcp_control_frame;			/* If it is a control frame goto rx_plcp_control_frame else it is a management frame*/
		je	RX_TYPE_SUBTYPE, TS_BEACON, rx_beacon_probe_resp;		
		je	RX_TYPE_SUBTYPE, TS_PROBE_REQ, send_response_if_ra_match;				
		je	RX_TYPE_SUBTYPE, TS_PROBE_RESP, rx_beacon_probe_resp;			
		jext	COND_TRUE, send_response_if_ra_match;			
	rx_plcp_control_frame:;							/* Control frame */
		je	RX_TYPE_SUBTYPE, TS_ACK, rx_ack;					
		je	RX_TYPE_SUBTYPE, TS_CTS, rx_ack;					
		and	RX_TYPE_SUBTYPE, 0xFFFB, GP_REG5;			/* GP_REG5 = RX_TYPE_SUBTYPE & ~0x04 */					
		jext	COND_TRUE, send_control_frame_to_host;			

// ***********************************************************************************************
// HANDLER:	rx_too_short
// PURPOSE:	Reports reception error and checks if frame must be kept.
//	
	rx_too_short:;
		mov	0x8300, SPR_WEP_CTL;					/* Disable crypto engine */
		orx	0, 9, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | RX_ERROR */
		jzx	0, 7, SPR_MAC_CTLHI, 0x000, start_frame_analysis;	/* if (!(SPR_MAC_Control_High & MCTL_KEEPBADFRAMES)) -- If I don't keep bad frames goto start_frame_analysis */			
		jext	COND_TRUE, state_machine_idle;				

// ***********************************************************************************************
// HANDLER:	rx_complete
// PURPOSE:	Completes reception and classifies frame. 
//
	rx_complete:;
		jext	COND_REC_IN_PROGRESS, clear_rxe_x1a;					
		extcond_eoi_only(COND_RX_COMPLETE);
		jext	COND_TRUE, update_RXE_FIFOCTL1_value;					
	clear_rxe_x1a:;
		jzx	0, 14, SPR_RXE_0x1a, 0x000, clear_rxe_x1a;		/* if (!(SPR_RXE_0x1a & 0x4000)) -- Wait for this condition to clear */			
		or	SPR_TSF_0x3e, 0x000, [SHM_RXHDR_MACTIME];		/* rx_hdr.RxTSFTime = SPR_TSF_0x3e -- Load TSF time into header */
		orx	0, 6, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~REC_IN_PROGRESS */
	wait_for_rec_completion:;
		jnext	EOI(COND_RX_COMPLETE), wait_for_rec_completion;				
		jg	SPR_RXE_FRAMELEN, [SHM_MAXPDULEN], rx_too_long;		/* if (SPR_RXE_RX_Frame_len >u shm_max_mpdu_len) -- Too long frame */
		jext	COND_RX_FCS_GOOD, frame_successfully_received;					
		jne	GPHY_SYM_WAR_FLAG, 0x000, frame_successfully_received;					
		orx	0, 9, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | RX_ERROR */			
		orx	0, 1, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~NEED_RESPONSEFR */
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;			
		orx	0, 0, 0x001, [SHM_RXHDR_MACST_LOW], [SHM_RXHDR_MACST_LOW];	/* rx_hdr.RxStatus1 = rx_hdr.RxStatus1 | 0x1 -- Bad FCS? */
		orx	0, 0, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;	/* GLOBAL_FLAGS_REG3 = RX_FRAME_DISCARD | (GLOBAL_FLAGS_REG3 & ~RX_FRAME_DISCARD) */				
		jext	COND_TRUE, send_frame_to_host;				
	frame_successfully_received:;
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;			
		jnext	COND_NEED_RESPONSEFR, check_frame_subtype;				
		jzx	0, 13, GLOBAL_FLAGS_REG3, 0x000, need_regular_ack;	/* if (!(GLOBAL_FLAGS_REG3 & NOT_REGULAR_ACK)) */
		orx	0, 1, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~NEED_RESPONSEFR */
		jext	COND_TRUE, check_frame_subtype;					
	need_regular_ack:;
		je	[SHM_CURMOD], 0x001, ofdm_modulation;			/* check if this response need short preamble */				
		jne	[SHM_CURMOD], 0x000, no_cck_modulation;			/* Not CCK modulation */
		jzx	3, 4, [0x01,off2], 0x000, ofdm_modulation;		/* if( ((mem[offs2 + 0x1] >> 4) & 0xF) == 0 ) */
	no_cck_modulation:;
		srx	0, 7, SPR_RXE_PHYRXSTAT0, 0x000, GP_REG5;		/* GP_REG5 = ((SPR_RXE_PHYRXSTAT0) >> 7) & 0x1, if set the received frame used short preamble */
		orx	0, 4, GP_REG5, SPR_TXE0_PHY_CTL, SPR_TXE0_PHY_CTL;	/* SPR_TXE0_PHY_Control = (((GP_REG5<<4) | (GP_REG5>>12)) & 0x10) | (SPR_TXE0_PHY_Control & ~0x10) */
	ofdm_modulation:;
		orx	0, 1, 0x001, [SHM_RXHDR_MACST_LOW], [SHM_RXHDR_MACST_LOW];	/* rx_hdr.RxStatus1 = rx_hdr.RxStatus1 | 0x2 */
		or	NEXT_TXE0_CTL, 0x000, SPR_TXE0_CTL;			/* SPR_TXE0_CTL = NEXT_TXE0_CTL */	
	check_frame_subtype:;
		srx	1, 0, RX_TYPE_SUBTYPE, 0x000, GP_REG5;			/* GP_REG5 = (RX_TYPE_SUBTYPE) & 0x3 */		
		je	GP_REG5, 0x001, rx_control_frame;			/* If it is a control frame goto rx_control_frame */
		jext	COND_RX_RAMATCH, rx_frame_and_ra_match;					
		jzx	0, 0, [RX_FRAME_ADDR1_1,off1], 0x000, not_multicast_frame;	/* if (!IS_MULTICAST(rx_frame)) */
		jne	RX_TYPE, 0x002, rx_not_data_frame_type;				/* if it is not a data frame (so it is a management frame) goto rx_not_data_frame_type*/
	rx_not_data_frame_type:;
		jnzx	0, 11, GLOBAL_FLAGS_REG3, 0x000, send_frame_to_host;	/* if (GLOBAL_FLAGS_REG3 & WDS_FRAME) */		
		jnzx	0, 8, [RX_FRAME_FC,off1], 0x000, discard_frame;		/* if (CTL_TO_DS(rx_frame) -- Management frame not sent to me, we can discard it*/
		jnzx	0, 9, [RX_FRAME_FC,off1], 0x000, control_frame_from_ds;	/* if (CTL_FROM_DS(rx_frame) -- Can be some management frame like beacon or probe response */
		jext	COND_RX_BSSMATCH, frame_from_our_BSS;			/* Is it a frame which belongs to our BSS? */
		jext	COND_TRUE, could_be_multicast_frame;					
	control_frame_from_ds:;
		jnext	0x62, could_be_multicast_frame;						
		je	RX_TYPE_SUBTYPE, TS_BEACON, frame_from_our_BSS;		/* A beacon from my AP! */		
		orx	0, 6, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;	/* GLOBAL_FLAGS_REG3 = GLOBAL_FLAGS_REG3 | 0x40 */				
	frame_from_our_BSS:;
		je	RX_TYPE_SUBTYPE, TS_PROBE_REQ, send_frame_to_host;	/* A probe request from a station within our BSS */						
		jext	COND_TRUE, send_frame_to_host;					
	not_multicast_frame:;
		jnext	0x3D, check_frame_type;						
		jnext	0x62, check_frame_type;						
		orx	0, 6, 0x000, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 := GLOBAL_FLAGS_REG3 & ~0x40 */				
	check_frame_type:;
		jne	RX_TYPE, 0x002, not_data_frame_and_ra_doesnt_match;		/* If it is not a data frame goto not_data_frame_and_ra_doesnt_match */		
		jext	COND_TRUE, data_frame_and_ra_doesnt_match;					
	could_be_multicast_frame:;
		je	RX_TYPE, 0x002, data_frame_and_ra_doesnt_match;			/* If it is a data frame goto data_frame_and_ra_doesnt_match */
		jnzx	0, 0, [RX_FRAME_ADDR3_1,off1], 0x000, send_frame_to_host;	/* if (mem[rx_frame_offs + FR_OFFS_ADDR3] & 0x01) -- Multicast frame? */
	not_data_frame_and_ra_doesnt_match:;
		jzx	0, 4, SPR_MAC_CTLHI, 0x000, data_frame_and_ra_doesnt_match;	/* if (!(SPR_MAC_Control_High & MCTL_BCNS_PROMISC) */
		je	RX_TYPE_SUBTYPE, TS_BEACON, send_frame_to_host;				
		je	RX_TYPE_SUBTYPE, TS_PROBE_RESP, send_frame_to_host;				
	data_frame_and_ra_doesnt_match:;
		jzx	0, 8, SPR_MAC_CTLHI, 0x000, discard_frame;		/* if (!(SPR_MAC_Control_High & MCTL_PROMISC)) */		
		jext	COND_TRUE, send_frame_to_host;				
	rx_control_frame:;
		jnext	COND_RX_RAMATCH, send_frame_to_host;			
		je	RX_TYPE_SUBTYPE, TS_RTS, send_frame_to_host;					
		je	RX_TYPE_SUBTYPE, TS_PSPOLL, send_frame_to_host;					
		jext	COND_TRUE, send_frame_to_host;				
	rx_frame_and_ra_match:;							/* Here frames whose RA match my address */
		jzx	0, 11, GLOBAL_FLAGS_REG3, 0x000, not_wds_frame;		/* if (!(GLOBAL_FLAGS_REG3 & WDS_FRAME)) */			
		jext	COND_TRUE, send_frame_to_host;				
	not_wds_frame:;
		jnext	COND_FRAME_NEED_ACK, send_frame_to_host;					
		srx	5, 2, [TXHDR_FCTL,off0], 0x000, GP_REG7;		/* GP_REG7 = ((tx_info.fctl) >> 2) & 0x3f */				

// ***********************************************************************************************
// HANDLER:	send_frame_to_host
// PURPOSE:	Prepares the frame before sending it to the host.
//
	send_frame_to_host:;
		jnzx	0, 7, SPR_MAC_CTLHI, 0x000, keep_bad_frames;		/* if (SPR_MAC_Control_High & MCTL_KEEPBADFRAMES) -- Keep bad frame for the Linux driver */
		jnzx	0, 0, GLOBAL_FLAGS_REG3, 0x000, discard_frame;		/* if (GLOBAL_FLAGS_REG3 & RX_FRAME_DISCARD) -- If I don't keep bad frame set discard frame bit */	
	keep_bad_frames:;
		or	SPR_RXE_FRAMELEN, 0x000, GP_REG5;			/* GP_REG5 = SPR_RXE_RX_Frame_len */
		or	GP_REG5, 0x000, [SHM_RXHDR_FLEN];			/* rx_hdr.RxFrameSize = GP_REG5 */
		jzx	0, 5, SPR_RXE_FIFOCTL1, 0x000, no_hdr_length_update;	/* if (!(SPR_RXE_FIFOCTL1 & 0x20)) */
		add	GP_REG5, [SHM_RXPADOFF], [SHM_RXHDR_FLEN];		/* rx_hdr.RxFrameSize = GP_REG5 + shm_rx_pad_data_offset */
		orx	0, 2, 0x001, [SHM_RXHDR_MACST_LOW], [SHM_RXHDR_MACST_LOW];	/* rx_hdr.RxStatus1 = rx_hdr.RxStatus1 | 0x4: tell Linux we have padding */
	no_hdr_length_update:;
		srx	0, 4, GLOBAL_FLAGS_REG3, 0x000, GP_REG5;		/* GP_REG5 = ((GLOBAL_FLAGS_REG3) >> 4) & 0x1 -- 1 if I received a beacon (not sure) */		
		orx	0, 15, GP_REG5, [SHM_RXHDR_MACST_LOW], [SHM_RXHDR_MACST_LOW];	/* rx_hdr.RxStatus1 = (((GP_REG5<<15) | (GP_REG5>>1)) & 0x8000) | (rx_hdr.RxStatus1 & ~0x8000) */
	wait_crypto_engine:;
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;			
		jext	COND_RX_CRYPTBUSY, wait_crypto_engine;				
		srx	0, 15, SPR_WEP_CTL, 0x000, GP_REG5;			/* GP_REG5 = ((SPR_WEP_Control) >> 15) & 0x1 */				
		orx	0, 4, GP_REG5, [SHM_RXHDR_MACST_LOW], [SHM_RXHDR_MACST_LOW];	/* rx_hdr.RxStatus1 := (((GP_REG5<<4) | (GP_REG5>>12)) & 0x10) | (rx_hdr.RxStatus1 & ~0x10) */
		or	SPR_RXE_PHYRXSTAT0, 0x000, [SHM_RXHDR_PHYST0];		/* rx_hdr.PhyRxStatus_0 = SPR_RXE_PHYRS_0 */
		or	SPR_RXE_PHYRXSTAT1, 0x000, [SHM_RXHDR_PHYST1];		/* rx_hdr.PhyRxStatus_1 = SPR_RXE_PHYRS_1 */
		or	SPR_RXE_PHYRXSTAT2, 0x000, [SHM_RXHDR_PHYST2];		/* rx_hdr.PhyRxStatus_2 = SPR_RXE_PHYRS_2 */
		or	SPR_RXE_PHYRXSTAT3, 0x000, [SHM_RXHDR_PHYST3];		/* rx_hdr.PhyRxStatus_3 = SPR_RXE_PHYRS_3 */
		srx	0, 5, SPR_RXE_PHYRXSTAT0, 0x000, [SHM_LAST_RX_ANTENNA];	/* shm_last_rx_antenna = ((SPR_RXE_PHYRS_0) >> 5) & 0x1 */
		mov	0xFFFE, ANTENNA_DIVERSITY_CTR;				
		call	lr1, antenna_diversity_helper;				
		call	lr0, push_frame_into_fifo;				
		nand	SPR_RXE_FIFOCTL1, 0x002, SPR_RXE_FIFOCTL1;		/* SPR_RXE_FIFOCTL1 = SPR_RXE_FIFOCTL1 & ~0x02 */		
		jext	COND_TRUE, tx_contention_params_update;					

// ***********************************************************************************************
// HANDLER:	rx_too_long
// PURPOSE:	Reports reception error.	
//
	rx_too_long:;			
		orx	0, 8, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | TX_ERROR */
		orx	0, 9, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | RX_ERROR */
		jext	COND_TRUE, discard_frame;				

// ***********************************************************************************************
// HANDLER:	rx_ack
// PURPOSE:i	Performs operations related to ACK reception.	
//
	rx_ack:;
		jnext	COND_RX_RAMATCH, send_control_frame_to_host;					
		jnext	COND_FRAME_NEED_ACK, send_control_frame_to_host;			
		jne	RX_TYPE_SUBTYPE, EXPECTED_CTL_RESPONSE, send_control_frame_to_host;			
		orx	0, 15, 0x000, SPR_TXE0_TIMEOUT, SPR_TXE0_TIMEOUT;			/* SPR_TXE0_TIMEOUT = SPR_TXE0_TIMEOUT & ~0x8000 */
		orx	0, 8, 0x000, SPR_BRC, SPR_BRC;						/* SPR_BRC = SPR_BRC & ~TX_ERROR */
		or	GP_REG5, 0x000, GP_REG5;					
		jle	0x000, 0x001, flush_pipe;
	flush_pipe:
		extcond_eoi_only(COND_TX_PMQ);
		jzx	0, 8, [SHM_HF_LO], 0x000, send_control_frame_to_host;			/* if (!(SHM_HF_LO & MHF_EDCF)) */
		jnext	0x28, send_control_frame_to_host;						
		orx	0, 9, 0x001, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;			/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 | 0x200 */								

// ***********************************************************************************************
// HANDLER:	send_control_frame_to_host
// PURPOSE:	Decides if control frame must be sent to host.	
//
	send_control_frame_to_host:;
		jext	COND_RX_RAMATCH, send_control_frame_and_ra_match;					
		jzx	0, 8, SPR_MAC_CTLHI, 0x000, rx_discard_frame;		/* if (!(SPR_MAC_Control_High & MCTL_PROMISC)) */	
	send_control_frame_and_ra_match:;
		jnzx	0, 6, SPR_MAC_CTLHI, 0x000, rx_complete;		/* if (SPR_MAC_Control_High & MCTL_KEEPCONTROL) */
		jext	COND_TRUE, rx_discard_frame;				

// ***********************************************************************************************
// HANDLER:	rx_check_promisc
// PURPOSE:	Controls if promiscuous mode was enable.	
//
	rx_check_promisc:;
		jnzx	0, 8, SPR_MAC_CTLHI, 0x000, rx_complete;		/* if (SPR_MAC_Control_High & MCTL_PROMISC) */	

// ***********************************************************************************************
// HANDLER:	rx_discard_frame	
// PURPOSE:	Commands a frame discard.
//
	rx_discard_frame:;
		orx	0, 0, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;	/* GLOBAL_FLAGS_REG3 = RX_FRAME_DISCARD | (GLOBAL_FLAGS_REG3 & ~RX_FRAME_DISCARD) */
		jext	COND_TRUE, rx_complete;								

// ***********************************************************************************************
// HANDLER:	rx_data_plus
// PURPOSE:	Manages data frame reception.	
//
	rx_data_plus:;
		jext	COND_RX_COMPLETE, end_rx_data_plus;					
		jl	SPR_RXE_FRAMELEN, 0x01C, rx_data_plus;			
	end_rx_data_plus:;
		jl	SPR_RXE_FRAMELEN, 0x01C, rx_check_promisc;		
		jnext	COND_RX_RAMATCH, rx_ra_dont_match;					
		jext	COND_TRUE, send_response;				

// ***********************************************************************************************
// HANDLER:	tx_underflow	
// PURPOSE:	Prepares device for TX underflow error management.	
//
	tx_underflow:;
		orx	0, 14, 0x001, [SHM_TXFCUR], SPR_TXE0_FIFO_CMD;		/* SPR_TXE0_FIFO_CMD = SHM_TXFCUR | 0x4000 */
		mov	0x0307, SPR_WEP_0x50;			 		
		orx	0, 8, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | TX_ERROR */
		jand	0x007, SPR_BRC, tx_fifo_underflow;			/* if !(SPR_BRC & (COND_NEED_BEACON | COND_NEED_RESPONSEFR | COND_NEED_PROBE_RESP)) */
		jext	COND_TRUE, check_underflow_cond;					

// ***********************************************************************************************
// HANDLER:	tx_fifo_underflow
// PURPOSE:	Manages TX underflow error.	
//
	tx_fifo_underflow:;
		mov	0x0076, GP_REG5;					/* GP_REG5 = M_TXFIFO_UFLO_OFFS */			
		srx	2, 8, [SHM_TXFCUR], 0x000, GP_REG6;			/* GP_REG6 = ((SHM_TXFCUR) >> 8) & 0x7 */
		add	GP_REG5, GP_REG6, SPR_BASE5;				/* SPR_BASE5 = GP_REG5 + GP_REG6 */
		add	[0x00,off5], 0x001, [0x00,off5];			
		orx	2, 2, 0x006, [TXHDR_STAT,off0], [TXHDR_STAT,off0];	/* tx_info.tx_status = SUPP_BUF_UFLO | (tx_info.tx_status & ~SUPPRESS_MASK) */
	tx_clear_issues:;
		mov	0x0001, GP_REG7;				
	tx_dont_clear_issues:;
		jnext	COND_FRAME_NEED_ACK, check_underflow_cond;					
		orx	0, 7, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~FRAME_NEED_ACK */				
		mov	0, EXPECTED_CTL_RESPONSE;				
		orx	0, 15, 0x000, SPR_TXE0_TIMEOUT, SPR_TXE0_TIMEOUT;	/* SPR_TXE0_TIMEOUT = SPR_TXE0_TIMEOUT & ~0x8000 */
		orx	0, 4, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~MORE_FRAGMENT */
		call	lr1, set_backoff_time;					
	check_underflow_cond:;
		extcond_eoi_only(COND_TX_POWER);
		extcond_eoi_only(COND_TX_NOW);
		orx	0, 5, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~FRAME_BURST */	
		extcond_eoi_only(COND_TX_UNDERFLOW);
		mov	0, SPR_TXE0_SELECT;			
		mov	0x0007, GP_REG5;				
		je	[SHM_PHYTYPE], 0x000, end_tx_fifo_underflow;		/* if (shm_phy_type == PHY_TYPE_A) */		
		orx	0, 10, SPR_TXE0_PHY_CTL, GP_REG5, GP_REG5;		/* GP_REG5 = (((SPR_TXE0_PHY_Control<<10) | (SPR_TXE0_PHY_Control>>6)) & 0x400) | (GP_REG5 & ~0x400) */
	end_tx_fifo_underflow:;
		call	lr0, sel_phy_reg;					
		or	SPR_Ext_IHR_Data, 0x000, GP_REG9;			/* GP_REG9 = SPR_Ext_IHR_Data */		
		mov	0xFFFF, GP_REG6;				
		call	lr0, write_phy_reg;					
		xor	GP_REG5, GP_REG8, GP_REG5;						
		call	lr0, write_phy_reg;					
		je	GP_REG7, 0x000, state_machine_idle;				
		or	GP_REG9, 0x000, [TXHDR_RTSPHYSTAT,off0];				
		jext	COND_TRUE, suppress_this_frame;				

// ***********************************************************************************************
// HANDLER:	tx_phy_error
// PURPOSE:	Manages TX phy errors.
//
	tx_phy_error:;
		jext	COND_FRAME_BURST, check_rx_conditions;
		jext	COND_FRAME_NEED_ACK, tx_clear_issues; 
		mov	0, GP_REG7;
		jext	COND_TRUE, tx_dont_clear_issues;

// ***********************************************************************************************
// HANDLER:	rx_fifo_overflow	
// PURPOSE:	Manages RX overflow error.	
//		Is the first instruction useful to clear some hardware exception? Can be safely removed?
//
	rx_fifo_overflow:;
		jg	SPR_RXE_FRAMELEN, [SHM_MAXPDULEN], overflow_frame_too_long;	/* if (SPR_RXE_RX_Frame_len >u shm_max_mpdu_len) */		
	overflow_frame_too_long:;
		jext	COND_REC_IN_PROGRESS, rx_complete;					
		extcond_eoi_only(COND_RX_FIFOFULL);
		orx	0, 9, 0x001, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC | RX_ERROR */		
		jext	COND_TRUE, discard_frame;				

// ***********************************************************************************************
// HANDLER:	mac_suspend_check	
// PURPOSE:	Checks if device can be suspended.
//		The condition on SPR_BRC involves
//		COND_NEED_RESPONSEFR|COND_FRAME_BURST|COND_REC_IN_PROGRESS|COND_FRAME_NEED_ACK
//
	mac_suspend_check:;
		jnand	0x0E2, SPR_BRC, check_conditions;			/* if (0xe2 & SPR_BRC) */			
		jnzx	0, 8, SPR_IFS_STAT, 0x000, check_conditions;				
		jext	COND_TX_DONE, check_conditions;				
		jext	COND_TX_PHYERR, check_conditions;			

		mov	0x002, GP_REG11;
		jext	COND_TRUE, flush_and_stop_tx_engine;	
	return_flush_into_mac_suspend_check:
			
// ***********************************************************************************************
// HANDLER:	mac_suspend	
// PURPOSE:	Suspends device.
//		
	mac_suspend:;
		mov	0x0001, SPR_MAC_IRQLO;					/* SPR_MAC_Interrupt_Status_Low = MI_MACSSPNDD */		
		mov	0x0003, [SHM_UCODESTAT];				/* shm_debug_status = DBGST_SUSPENDED */
		mov	0x0303, SPR_WEP_0x50;					/* SPR_WEP_0x50 = 0x0303 */
	wait_for_mac_to_disable:;
		jnext	COND_MACEN, wait_for_mac_to_disable;					
		mov	0x0002, [SHM_UCODESTAT];				/* shm_debug_status = DBGST_ACTIVE */			
		srx	0, 15, SPR_MAC_CTLHI, 0x000, GLOBAL_FLAGS_REG1;		/* GLOBAL_FLAGS_REG1 = ((SPR_MAC_Control_High) >> 15) & GMODE */ 
		mov	0x0301, SPR_WEP_0x50;					/* SPR_WEP_0x50 = 0x0301 */
		mov	0x8300, SPR_WEP_CTL;					/* Disable hardware crypto */
		mov	0, SPR_BRC;						
		nand	GLOBAL_FLAGS_REG2, 0x01A, GLOBAL_FLAGS_REG2;		/* GLOBAL_FLAGS_REG2 = GLOBAL_FLAGS_REG2 & ~AFTERBURNER_TX|0x18 */			
		mov	0xFFFF, SPR_BRCL0;				
		mov	0xFFFF, SPR_BRCL1;				
		mov	0xFFFF, SPR_BRCL2;				
		mov	0xFFFF, SPR_BRCL3;				
		orx	0, 2, 0x001, SPR_RXE_FIFOCTL1, SPR_RXE_FIFOCTL1;			/* SPR_RXE_FIFOCTL1 = SPR_RXE_FIFOCTL1 | 0x4 */
	wait_RXE_FIFOCTL1_cond_to_clear:;
		jnzx	0, 2, SPR_RXE_FIFOCTL1, 0x000, wait_RXE_FIFOCTL1_cond_to_clear;		/* if (SPR_RXE_FIFOCTL1 & 0x04) */
		mov	0, SPR_BRCL0;				
		mov	0, SPR_BRCL1;				
		mov	0, SPR_BRCL2;				
		mov	0, SPR_BRCL3;				
		srx	0, 14, SPR_MAC_CTLHI, 0x000, GP_REG5;			/* GP_REG5 = ((SPR_MAC_Control_High) >> 14) & 0x1 */
		xor	GP_REG5, 0x001, GP_REG5;					
		mov	0x7360, SPR_BRWK0;				
		mov	0, SPR_BRWK1;				
		mov	0x730F, SPR_BRWK2;				
		mov	0x0057, SPR_BRWK3;				
		jext	COND_TRUE, state_machine_start;				

// ***********************************************************************************************
// HANDLER:	rx_badplcp	
// PURPOSE:	Manages reception of a frame with not valid PLCP.
//
	rx_badplcp:;
		jnzx	0, 11, SPR_RXE_0x1a, 0x000, state_machine_idle;		/* if (SPR_RXE_0x1a & 0x800) */
		jnzx	0, 12, SPR_RXE_0x1a, 0x000, rx_badplcp;			/* if (SPR_RXE_0x1a & 0x1000) */
		orx	0, 4, 0x001, GLOBAL_FLAGS_REG2, GLOBAL_FLAGS_REG2;	/* GLOBAL_FLAGS_REG2 = GLOBAL_FLAGS_REG2 | 0x10 */				
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;			
		jnzx	0, 15, SPR_RXE_0x1a, 0x000, rx_fifo_overflow;		
	update_RXE_FIFOCTL1_value:;
		mov	0x0004, SPR_RXE_FIFOCTL1;				/* SPR_RXE_FIFOCTL1 = 0x0004 */
		or	SPR_RXE_FIFOCTL1, 0x000, GP_REG5;			/* GP_REG5 = SPR_RXE_FIFOCTL1 */ 
		jext	COND_TRUE, state_machine_start;				

// ***********************************************************************************************
// HANDLER:	discard_frame	
// PURPOSE:	Discards the frame into the FIFO.
//
	discard_frame:;
		mov	0x0014, SPR_RXE_FIFOCTL1;								
		or	SPR_RXE_FIFOCTL1, 0x000, 0x000;				/* 0x000 = SPR_RXE_FIFOCTL1 */				
		srx	2, 5, SPR_WEP_CTL, 0x000, GP_REG5;			/* GP_REG5 = ((SPR_WEP_Control) >> 5) & 0x7 */
		jnext	COND_RX_ERROR, tx_contention_params_update;					
		orx	0, 12, 0x001, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 | 0x1000 */	
		mov	0x003, GP_REG11;			
		jext	COND_TRUE, flush_and_stop_tx_engine;
	return_flush_into_discard_frame:				
		orx	0, 0, 0x001, SPR_TXE0_AUX, SPR_TXE0_AUX;		/* SPR_TXE0_Aux = SPR_TXE0_Aux | 0x1 */
		or	GP_REG5, 0x000, GP_REG5;					
		orx	0, 0, 0x000, SPR_TXE0_AUX, SPR_TXE0_AUX;		/* SPR_TXE0_Aux = SPR_TXE0_Aux & ~0x1 */
		jext	COND_TRUE, tx_contention_params_update;					

// ***********************************************************************************************
// HANDLER:	flush_and_stop_tx_engine	
// PURPOSE:	Checks if there are any other frames into the queue, flushes the TX engine and stops it.
//
	flush_and_stop_tx_engine:;
		mov	0x4000, SPR_TXE0_CTL;					/* Enable FCS calculation */			
		or	SPR_TXE0_CTL, 0x000, 0x000;				/* 0x000 = SPR_TXE0_CTL */	
		jle	0x000, 0x001, check_pending_tx_and_stop;					
	check_pending_tx_and_stop:;
		jext	EOI(COND_TX_NOW), tx_frame_now;				
	pending_tx_resolved:;
		nand	SPR_BRC, 0x027, SPR_BRC;				/* SPR_BRC = (SPR_BRC & ~(FRAME_BURST | NEED_BEACON | NEED_RESPONSEFR | NEED_PROBE_RESP) */
		mov	0, SPR_TXE0_SELECT;					
		orx	0, 15, 0x000, SPR_TXE0_TIMEOUT, SPR_TXE0_TIMEOUT;	/* SPR_TXE0_TIMEOUT = SPR_TXE0_TIMEOUT & ~0x8000 */	
		orx	0, 4, 0x000, SPR_BRC, SPR_BRC;				/* SPR_BRC = SPR_BRC & ~MORE_FRAGMENT -- clear tx_more_frag bit */
		jnzx	0, 9, SPR_WEP_CTL, 0x000, jump_wep_update;		/* if (SPR_WEP_Control & 0x200) */
		orx	7, 8, 0x002, 0x000, SPR_WEP_CTL;			/* SPR_WEP_Control = 0x0200 */
	jump_wep_update:;
		orx	1, 12, 0x000, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 & ~0x3000 */	
		jne	GP_REG11, 0x001, no_prepare_beacon_tx_return;
		jext	COND_TRUE, return_flush_into_prepare_beacon_tx;
	no_prepare_beacon_tx_return:
		jne	GP_REG11, 0x002, no_mac_suspend_check_return;
		jext	COND_TRUE, return_flush_into_mac_suspend_check;
	no_mac_suspend_check_return:;	
		jne	GP_REG11, 0x003, no_discard_frame_return;
		jext	COND_TRUE, return_flush_into_discard_frame;
	no_discard_frame_return:
		jext	COND_TRUE, return_flush_into_rx_beacon;

// ***********************************************************************************************
// HANDLER:	rx_beacon_probe_resp	
// PURPOSE:	Analyzes Beacon or Probe Response frame that has been received. Important for time synchronization.
//		off3 is a pointer that has been load before by get_ptr_from_rate_table with a value coming
//		from the second level rate tables, e.g., on a beacon in 2.4MHz off3 = 0x37E
//
	rx_beacon_probe_resp:;
		jl	SPR_RXE_FRAMELEN, 0x02C, rx_discard_frame;		
		jext	COND_RX_BSSMATCH, rx_bss_match;					
		je	RX_TYPE_SUBTYPE, TS_PROBE_RESP, rx_beacon_probe_resp_end;
		jext	COND_TRUE, no_time_informations;					
	rx_bss_match:;
		je	RX_TYPE_SUBTYPE, TS_PROBE_RESP, check_beacon_time;
		jext	0x3E, rx_beacon_probe_resp_end;	
		jext	0x3D, check_beacon_time;	
		jext	COND_CONTENTION_PARAM_MODIFIED, check_beacon_time;
		mov	0x004, GP_REG11;
		jext	COND_TRUE, flush_and_stop_tx_engine;
	return_flush_into_rx_beacon:;
		extcond_eoi_only(COND_TX_TBTTEXPIRE);
		orx     0, 0, 0x000, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC & ~NEED_BEACON */
		orx     0, 3, 0x000, SPR_BRC, SPR_BRC;					/* SPR_BRC = SPR_BRC & ~CONTENTION_PARAM_MODIFIED */
		orx     7, 8, 0x000, 0x010, SPR_MAC_IRQLO;
		jnzx    0, 0, SPR_TSF_0x0e, 0x000, succ_bcn_tx;
		or      NEXT_IFS, 0x000, SPR_IFS_BKOFFDELAY;
		orx     7, 8, 0x000, 0x000, NEXT_IFS;
		or      NEXT_CONTENTION_WIN, 0x000, CUR_CONTENTION_WIN;
		or      MIN_CONTENTION_WIN, 0x000, NEXT_CONTENTION_WIN;
		jext    COND_TRUE, check_beacon_time;
	succ_bcn_tx:
		and     SPR_TSF_Random, MIN_CONTENTION_WIN, SPR_IFS_BKOFFDELAY;
	check_beacon_time:;
		jext	0x3E, rx_beacon_probe_resp_end;						
		or	[SHM_TBL_OFF2DUR], 0x000, GP_REG5;					
		add	GP_REG5, [0x00,off3], GP_REG5;					
		add.	RX_TIME_WORD0, GP_REG5, RX_TIME_WORD0;						
		addc.	RX_TIME_WORD1, 0x000, RX_TIME_WORD1;					
		addc.	RX_TIME_WORD2, 0x000, RX_TIME_WORD2;					
		addc	RX_TIME_WORD3, 0x000, RX_TIME_WORD3;					
		jext	0x3D, sync_TSF;						
		jg	RX_TIME_WORD3, [RX_FRAME_BCN_TIMESTAMP_3,off1], rx_beacon_probe_resp_end;		/* if (rx_time_word_3 >u mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_3]) */
		jl	RX_TIME_WORD3, [RX_FRAME_BCN_TIMESTAMP_3,off1], sync_TSF;				/* if (rx_time_word_3 <u mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_3]) */
		jg	RX_TIME_WORD2, [RX_FRAME_BCN_TIMESTAMP_2,off1], rx_beacon_probe_resp_end;		/* if (rx_time_word_2 >u mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_2]) */		
		jl	RX_TIME_WORD2, [RX_FRAME_BCN_TIMESTAMP_2,off1], sync_TSF;				/* if (rx_time_word_2 <u mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_2]) */		
		jg	RX_TIME_WORD1, [RX_FRAME_BCN_TIMESTAMP_1,off1], rx_beacon_probe_resp_end;		/* if (rx_time_word_1 >u mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_1]) */		
		jl	RX_TIME_WORD1, [RX_FRAME_BCN_TIMESTAMP_1,off1], sync_TSF;				/* if (rx_time_word_1 <u mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_1]) */		
		jge	RX_TIME_WORD0, [RX_FRAME_BCN_TIMESTAMP_0,off1], rx_beacon_probe_resp_end;		/* if (rx_time_word_0 >=u mem[rx_frame_offs + FR_OFFS_DATA]) */		
	sync_TSF:;
		or	SPR_TSF_WORD0, 0x000, [SHM_RX_TIME_WORD0];				
		or	SPR_TSF_WORD1, 0x000, [SHM_RX_TIME_WORD1];				
		or	SPR_TSF_WORD2, 0x000, [SHM_RX_TIME_WORD2];				
		or	SPR_TSF_WORD3, 0x000, [SHM_RX_TIME_WORD3];				
		jne	[SHM_RX_TIME_WORD0], SPR_TSF_WORD0, sync_TSF;				
		sub.	[SHM_RX_TIME_WORD0], RX_TIME_WORD0, RX_TIME_WORD0;					
		subc.	[SHM_RX_TIME_WORD1], RX_TIME_WORD1, RX_TIME_WORD1;					
		subc.	[SHM_RX_TIME_WORD2], RX_TIME_WORD2, RX_TIME_WORD2;					
		subc	[SHM_RX_TIME_WORD3], RX_TIME_WORD3, RX_TIME_WORD3;					
	update_TSF_words:;
		add.	RX_TIME_WORD0, [RX_FRAME_BCN_TIMESTAMP_0,off1], GP_REG5;					
		or	GP_REG5, 0x000, SPR_TSF_WORD0;				
		addc.	RX_TIME_WORD1, [RX_FRAME_BCN_TIMESTAMP_1,off1], SPR_TSF_WORD1;	/* SPR_TSF_word_1 = rx_time_word_1 + mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_1] + carry [set carry] */	
		addc.	RX_TIME_WORD2, [RX_FRAME_BCN_TIMESTAMP_2,off1], SPR_TSF_WORD2;	/* SPR_TSF_word_2 = rx_time_word_2 + mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_2] + carry [set carry] */	
		addc.	RX_TIME_WORD3, [RX_FRAME_BCN_TIMESTAMP_3,off1], SPR_TSF_WORD3;	/* SPR_TSF_word_3 = rx_time_word_3 + mem[rx_frame_offs + FR_OFFS_BCN_TIMESTAMP_3] + carry [set carry] */
		jne	GP_REG5, SPR_TSF_WORD0, update_TSF_words;				
		jnext	0x3D, rx_beacon_probe_resp_end;						
	no_time_informations:;
		je	RX_TYPE_SUBTYPE, TS_PROBE_RESP, rx_beacon_probe_resp_end;					
		mov	0x051D, SPR_BASE5;						/* 0x51d = rx_frame_offs + 42 --> plcp + fixed beacon fields */			
		mov	0x0004, GP_REG8;				
		call	lr0, find_dtim_info_elem;						
		jnext	0x3D, rx_beacon_probe_resp_end;						
		jext	0x3E, rx_beacon_probe_resp_end;			
		jnext	COND_RX_BSSMATCH, rx_beacon_probe_resp_end;
		je	RX_TYPE_SUBTYPE, TS_PROBE_RESP, rx_beacon_probe_resp_end;					
		mov	0x0005, GP_REG8;				
		call	lr0, find_dtim_info_elem;						
		jne	GP_REG8, 0x005, rx_beacon_probe_resp_end;					
		srx	7, 8, [0x01,off5], 0x000, CURRENT_DTIM_COUNT;			/* current_dtim_count = ((mem[offs5 + 0x1]) >> 8) & 0xff */			
		srx	7, 8, [0x02,off5], 0x000, GP_REG5;				/* GP_REG5 = ((mem[offs5 + 0x2]) >> 8) & 0xff */
		orx	0, 6, GP_REG5, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 = (((GP_REG5<<6) | (GP_REG5>>10)) & 0x40) | (GLOBAL_FLAGS_REG3 & ~0x40) */				
		orx	0, 15, GP_REG5, SPR_TSF_GPT1_STAT, SPR_TSF_GPT1_STAT;		/* SPR_TSF_GPT1_Stat = (((GP_REG5<<15) | (GP_REG5>>1)) & 0x8000) | (SPR_TSF_GPT1_Stat & ~TSF_GPT_ENABLE) */
	rx_beacon_probe_resp_end:;
		jext	COND_RX_RAMATCH, send_response;				
		jext	COND_TRUE, rx_complete;					

// ***********************************************************************************************
// HANDLER:	send_response_if_ra_match
// PURPOSE:	Decides if frame needs a response.
//
	send_response_if_ra_match:;
		jext	COND_RX_RAMATCH, send_response;				
	rx_ra_dont_match:;
		jzx	0, 0, [RX_FRAME_ADDR1_1,off1], 0x000, rx_check_promisc;		/* if (!IS_MULTICAST(rx_frame)) */	
		jext	COND_TRUE, rx_complete;					

// ***********************************************************************************************
// HANDLER:	slow_clock_control
// PURPOSE:	Updates SCC.
//
	slow_clock_control:
	        jnand   0x0FF, SPR_BRC, state_machine_idle;
        	jnzx    0, 2, GLOBAL_FLAGS_REG3, 0x000, skip_scc_update;
	        jnzx    0, 1, SPR_SCC_Control, 0x000, state_machine_idle;
        	orx     14, 1, SPR_SCC_Timer_Low, 0x000, SPR_SCC_Period_Divisor;
	        srx     0, 15, SPR_SCC_Timer_Low, 0x000, GP_REG5;
        	orx     14, 1, SPR_SCC_Timer_High, GP_REG5, SPR_SCC_Period;
	        orx     0, 2, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;
	skip_scc_update:
		jext	COND_TRUE, state_machine_idle;


/* --------------------------------------------------- FUNCTIONS ---------------------------------------------------------- */


// ***********************************************************************************************
// FUNCTION:	push_frame_into_fifo
// PURPOSE:	Copies received frame into the RX host queue.
//
	push_frame_into_fifo:;							/* Set frame offset and header length */
		mov	SHM_RXHDR, SPR_RXE_RXHDR_OFFSET;		
		mov	SHM_RXHDR_LEN, SPR_RXE_RXHDR_LEN;			
		orx	1, 0, 0x001, SPR_RXE_FIFOCTL1, SPR_RXE_FIFOCTL1;	/* SPR_RXE_FIFOCTL1 = (SPR_RXE_FIFOCTL1 & ~0x3) | 0x1 */
	wait_rx_fifo_1:;
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;			/* Wait for the engine to stop its work */		
		jnext	COND_RX_FIFOBUSY, wait_rx_fifo_1;					
	wait_rx_fifo_2:;
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;			
		jext	COND_RX_FIFOBUSY, wait_rx_fifo_2;					
		or	GP_REG5, 0x000, GP_REG5;					
		jle	0x000, 0x001, check_rx_fifo_overflow;					
	check_rx_fifo_overflow:;
		jext	COND_RX_FIFOFULL, rx_fifo_overflow;				
		mov	0x0100, SPR_MAC_IRQLO;					/* SPR_MAC_Interrupt_Status_Low = MI_NSPECGEN_1 -- There is a frame ready in the fifo */
		ret	lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	load_tx_header_into_shm
// PURPOSE:	Loads BCM header into SHM.
//
	load_tx_header_into_shm:;
		mov	SHM_TXHEADER, SPR_BASE0;				/* off0 = SHM_TXHEADER */
		mov	0x0000, GP_REG5;
		jnzx	0, 1, [TXHDR_HK4,off0], 0x000, load_tx_hdr_done;	/* if (tx_info.housekeeping4 & 0x02) */
		orx	0, 14, 0x001, [SHM_TXFCUR], SPR_TXE0_FIFO_CMD;		/* SPR_TXE0_FIFO_CMD = SHM_TXFCUR | 0x4000 */
		sl	SPR_BASE0, 0x001, SPR_TXE0_TX_SHM_ADDR;			/* SPR_TXE0_TX_SHM_ADDR = SPR_BASE0 << 0x01 */
		or	[SHM_TXFCUR], 0x000, SPR_TXE0_SELECT;			/* SPR_TXE0_SELECT = SHM_TXFCUR */
		mov	TXHDR_LEN, SPR_TXE0_TX_COUNT;			
		or	[SHM_TXFCUR], 0x005, SPR_TXE0_SELECT;			/* SPR_TXE0_SELECT = SHM_TXFCUR | 0x05 */			
	load_hdr_wait_for_tx_engine:;
		jnext	COND_TX_BUSY, load_hdr_wait_for_tx_engine;		/* Wait until header was copied from FIFO to SHM */
	load_hdr_wait_for_tx_engine_again:;
		jext	COND_TX_BUSY, load_hdr_wait_for_tx_engine_again;					
		orx	1, 0, 0x002, [TXHDR_HK4,off0], [TXHDR_HK4,off0];	/* tx_info.housekeeping4 = 0x2 | (tx_info.housekeeping4 & ~0x3) */
		jzx	0, 3, [TXHDR_MACLO,off0], 0x000, load_tx_hdr_done;	/* if (!(tx_info.MAC_ctl_lo & TX_CTL_START_MSDU)) */
		nand	[TXHDR_HK5,off0], 0x018, [TXHDR_HK5,off0];		/* tx_info.housekeeping5 = tx_info.housekeeping5 & ~(FAILED|USE_FALLBACK) */
	load_tx_hdr_done:;
		ret	lr3, lr3;

// ***********************************************************************************************
// FUNCTION:	inhibit_sleep_at_tbtt
// PURPOSE:	Forces device to not sleep at TBTT.
//
	inhibit_sleep_at_tbtt:;
        	orx     7, 8, 0x000, 0x004, SPR_MAC_IRQLO;
        	extcond_eoi_only(COND_TX_TBTTEXPIRE);
        	sl      [SHM_NOSLPZNATDTIM], 0x003, SPR_TSF_GPT1_CNTLO;
        	sr      [SHM_NOSLPZNATDTIM], 0x00D, SPR_TSF_GPT1_CNTHI;
        	orx     7, 8, 0x0C0, 0x000, SPR_TSF_GPT1_STAT;
        	ret     lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	sel_phy_reg
// PURPOSE:	Selects a phy register.
//
	sel_phy_reg:;
		jnzx	0, 14, SPR_Ext_IHR_Address, 0x000, sel_phy_reg;
		orx	0, 12, 0x001, GP_REG5, SPR_Ext_IHR_Address;
	wait_sel_phy_cond_to_clear:;
		jnzx	0, 12, SPR_Ext_IHR_Address, 0x000, wait_sel_phy_cond_to_clear;
		or	GP_REG5, 0x000, GP_REG5;
		ret	lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	write_phy_reg
// PURPOSE:	Writes the value contained in GP_REG6 into phy register. 
//
	write_phy_reg:;
		jnzx	0, 14, SPR_Ext_IHR_Address, 0x000, write_phy_reg;
		or	GP_REG6, 0x000, SPR_Ext_IHR_Data;
		orx	0, 13, 0x001, GP_REG5, SPR_Ext_IHR_Address;
		jnzx	0, 3, GLOBAL_FLAGS_REG1, 0x000, end_write_phy_reg;
	wait_write_phy_cond_to_clear:;
		jnzx	0, 13, SPR_Ext_IHR_Address, 0x000, wait_write_phy_cond_to_clear;
	end_write_phy_reg:;
		or	GP_REG5, 0x000, GP_REG5;
		ret	lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	get_ptr_from_rate_table
// PURPOSE:	Makes pointer refers to the correct premable informations.
//		It takes the rate in GP_REG0 and the control in GP_REG1
//		rate values (from the b43 driver, xmit.c)
//
//		cck  at [1, 2, 5, 11] => [ 0x0A, 0x14, 0x37, 0x6E ]
//		ofdm at [6, 9, 12, 18, 24, 36, 48, 54] => [0xB, 0xF, 0xA, 0xE, 0x9, 0xD, 0x8, 0xC]
//
//		e.g. on reception of a beacon we have gp_reg0 = 0x0A and gp_reg1 = 0x00
//
	get_ptr_from_rate_table:;
		mov	0x14, [SHM_PREAMBLE_DURATION];				/* SHM_PREAMBLE_DURATION = 0x14 */				
		orx	11, 4, 0x000, GP_REG0, GP_REG0;				/* GP_REG0 = GP_REG0 & ~0xFFF0 */	
		je	[SHM_PHYTYPE], 0x000, get_ptr_from_rate_table_ofdm;	/* OFDM phy type */	
		jzx	1, 0, GP_REG1, 0x000, get_ptr_from_rate_table_cck;	
	get_ptr_from_rate_table_ofdm:;
		mov	SHM_OFDMDIRECT, GP_REG5;				
		add	GP_REG0, GP_REG5, SPR_BASE5;				/* SPR_BASE5 = GP_REG0 + GP_REG5 */						
		add	GP_REG0, GP_REG5, SPR_BASE4;				/* SPR_BASE4 = GP_REG0 + GP_REG5 */						
		mov	0x0001, [SHM_CURMOD];					/* [SHM_CURMOD] = 1 -> OFDM */
		jext	COND_TRUE, get_ptr_from_rate_table_out;			
	get_ptr_from_rate_table_cck:;
		mov	SHM_CCKDIRECT, GP_REG5;				
		add	GP_REG0, GP_REG5, SPR_BASE5;				/* SPR_BASE5 = GP_REG0 + GP_REG5 */					
		add	GP_REG0, GP_REG5, SPR_BASE4;				/* SPR_BASE4 = GP_REG0 + GP_REG5 */		
		mov	0x00C0, [SHM_PREAMBLE_DURATION];			/* SHM_PREAMBLE_DURATION = 0xC0 */			
		mov	0, [SHM_CURMOD];					/* [SHM_CURMOD] = 0 -> CCK */
	get_ptr_from_rate_table_out:;
		or	[0x00,off5], 0x000, SPR_BASE2;				/* SPR_BASE2 = [0x00,off5] */
		or	[0x00,off4], 0x000, SPR_BASE3;				/* SPR_BASE3 = [0x00,off4] */	
		ret	lr0, lr0;						

// ***********************************************************************************************
// FUNCTION:	find_dtim_info_elem
// PURPOSE:	Extracts TIM informations from Beacon frame.
//
	find_dtim_info_elem:;
		sub	SPR_RXE_FRAMELEN, 0x004, GP_REG5;			/* GP_REG5 = SPR_RXE_RX_FRAMELEN - 0x04 */			
		or	SPR_RXE_Copy_Length, 0x000, GP_REG7;			/* GP_REG7 = SPR_RXE_Copy_Length */
		jl	GP_REG5, GP_REG7, align_offset_1;			/* if (GP_REG5 <u GP_REG7) */
		sr	GP_REG7, 0x001, GP_REG7;				/* GP_REG7 = GP_REG7 >> 0x01 */
		jext	COND_TRUE, align_offset_2;						
	align_offset_1:;
		sr	GP_REG5, 0x001, GP_REG7;				/* GP_REG7 = GP_REG5 >> 0x01 */
	align_offset_2:;
		add	GP_REG7, SPR_RXE_Copy_Offset, GP_REG7;			/* GP_REG7 = GP_REG7 + SPR_RXE_Copy_Offset */
	loop_inside_beacon_infos:;
		orx	14, 0, SPR_BASE5, 0x000, GP_REG5;			/* GP_REG5 = offs5 & 0x7fff */
		jge	GP_REG5, GP_REG7, update_return_value;			/* if (GP_REG5 >=u GP_REG7) */
		jnzx	0, 15, SPR_BASE5, 0x000, extract_beacon_informations;	/* if (offs5 & 0x8000) */
		srx	7, 0, [0x00,off5], 0x000, GP_REG5;			/* GP_REG5 = (mem[offs5 + 0x0]) & 0xff */
		srx	7, 8, [0x00,off5], 0x000, GP_REG6;			/* GP_REG6 = ((mem[offs5 + 0x0]) >> 8) & 0xff */
		jext	COND_TRUE, compute_oper_on_infos;						
	extract_beacon_informations:;
		srx	7, 8, [0x00,off5], 0x000, GP_REG5;			/* GP_REG5 = ((mem[offs5 + 0x0]) >> 8) & 0xff */
		srx	7, 0, [0x01,off5], 0x000, GP_REG6;			/* GP_REG6 = (mem[offs5 + 0x1]) & 0xff */
	compute_oper_on_infos:;
		jge	GP_REG5, GP_REG8, finish_operations_on_beacon;		/* if (GP_REG5 >=u GP_REG8) */
		rr	GP_REG6, 0x001, GP_REG6;				/* GP_REG6 = (GP_REG6 >> 0x01) | (GP_REG6 << (16 - 0x01)) */
		add.	SPR_BASE5, GP_REG6, SPR_BASE5;				/* offs5 = offs5 + GP_REG6 [set carry] */
		addc.	SPR_BASE5, 0x001, SPR_BASE5;				/* offs5 = offs5 + 0x01 + carry [set carry] */
		jext	COND_TRUE, loop_inside_beacon_infos;						
	finish_operations_on_beacon:;
		jne	GP_REG5, GP_REG8, update_return_value;			/* if (GP_REG5 != GP_REG8) */
		rr	GP_REG6, 0x001, GP_REG6;				/* GP_REG6 = (GP_REG6 >> 0x01) | (GP_REG6 << (16 - 0x01)) */
		add.	SPR_BASE5, GP_REG6, GP_REG5;				/* GP_REG5 = offs5 + GP_REG6 [set carry] */
		addc.	GP_REG5, 0x001, GP_REG5;				/* GP_REG5 = GP_REG5 + 0x01 + carry [set carry] */
		orx	14, 0, GP_REG5, 0x000, GP_REG5;				/* GP_REG5 = GP_REG5 & 0x7fff */
		jle	GP_REG5, GP_REG7, end_find_dtim_info_elem;		/* if (GP_REG5 <=u GP_REG7) goto end_find_dtim_info_elem */
	update_return_value:;
		mov	0xFFFF, GP_REG8;					/* GP_REG8 = 0xffff */
	end_find_dtim_info_elem:;
		ret	lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	prep_phy_txctl_with_encoding	
// PURPOSE:	Sets PHY parameters correctly according to the transmission needs.
//
	prep_phy_txctl_with_encoding:;
		orx	1, 0, GP_REG1, SPR_TXE0_PHY_CTL, SPR_TXE0_PHY_CTL;		/* SPR_TXE0_PHY_CTL = (r1 & 0x3) | (SPR_TXE0_PHY_CTL & ~0x3) */		
	prep_phy_txctl_encoding_already_set:
		jzx	0, 9, SPR_TXE0_PHY_CTL, 0x000, no_phy_control_update;		/* if (!(SPR_TXE0_PHY_Control & 0x200)) */
		orx	1, 8, [SHM_LAST_RX_ANTENNA], SPR_TXE0_PHY_CTL, SPR_TXE0_PHY_CTL;	/* SPR_TXE0_PHY_CTL = (((shm_last_rx_antenna<<8) | (shm_last_rx_antenna>>8)) & 0x300) | (SPR_TXE0_PHY_CTL & ~0x300) */
	no_phy_control_update:;
		jzx	0, 7, [SHM_HF_MI], 0x000, end_prep_phy_txctl_with_encoding;	/* if (!(SHM_HF_MI & MHF_HWPWRCTL)) */
		or	[SHM_TXPWRCUR], 0x000, GP_REG5;					/* GP_REG5 = shm_tx_pwr_cur */
		add	GP_REG5, [0x07,off5], GP_REG5;					/* GP_REG5 = GP_REG5 + mem[offs5 + 0x7] */
		orx	5, 10, GP_REG5, SPR_TXE0_PHY_CTL, SPR_TXE0_PHY_CTL;		/* SPR_TXE0_PHY_CTL = (((GP_REG5<<10) | (GP_REG5>>6)) & 0xfc00) | (SPR_TXE0_PHY_Control & ~0xfc00) */
	end_prep_phy_txctl_with_encoding:;
		ret	lr1, lr1;

// ***********************************************************************************************
// FUNCTION:	get_rate_table_duration
// PURPOSE:	Provides duration parameter.
//		If short preamble is requested, then subracts half of the preamble duration
//		to overall duration
//
	get_rate_table_duration:;
		or	[0x04,off2], 0x000, GP_REG5;				/* GP_REG5 = mem[offs2 + 0x4] */		
		jzx	0, 4, GP_REG1, 0x000, end_get_rate_table_duration;	/* if !(GP_REG1 & 0x10) */
		jnzx	0, 0, GP_REG1, 0x000, end_get_rate_table_duration;	/* if (GP_REG1 &0x01) */
		sr	[SHM_PREAMBLE_DURATION], 0x001, GP_REG6;		/* GP_REG6 := shm_preamble_duration >> 0x01 */	
		sub	[0x04,off2], GP_REG6, GP_REG5;				/* GP_REG5 := mem[offs2 + 0x4] - GP_REG6 */	
	end_get_rate_table_duration:;
		ret	lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	antenna_diversity_helper
// PURPOSE:	Manages antenna diversity operations.
//
	antenna_diversity_helper:;
		jzx	0, 0, [SHM_HF_LO], 0x000, end_antenna_diversity_helper;			/* if (!(SHM_HF_LO & MHF_ANTDIV)) */
		add	ANTENNA_DIVERSITY_CTR, 0x001, ANTENNA_DIVERSITY_CTR;			/* antenna_diversity_counter++ */				
		jl	ANTENNA_DIVERSITY_CTR, [SHM_ANTSWAP], end_antenna_diversity_helper;	/* if (antenna_diversity_counter <u shm_antenna_swap_thresh) */		
		mov	0x0001, GP_REG5;							/* GP_REG5 = BPHY_BB_CONFIG */
		je	[SHM_PHYTYPE], 0x001, B_phy;						/* if (shm_phy_type == PHY_TYPE_B) */
		orx	0, 10, GLOBAL_FLAGS_REG1, 0x02B, GP_REG5;				/* GP_REG5 = (((GLOBAL_FLAGS_REG1<<10) | (GLOBAL_FLAGS_REG1>>6)) & 0x400) | APHY_ANT_DWELL */		
	B_phy:;
		call	lr0, sel_phy_reg;					
		jne	ANTENNA_DIVERSITY_CTR, 0xFFFF, no_antenna_update;			/* if (antenna_diversity_counter != ~0x00) */		
		orx	0, 7, [SHM_LAST_RX_ANTENNA], SPR_Ext_IHR_Data, GP_REG6;			/* GP_REG6 = (((shm_last_rx_antenna<<7) | (shm_last_rx_antenna>>9)) & 0x80) | (SPR_Ext_IHR_Data & ~0x80) */
		je	[SHM_PHYTYPE], 0x001, B_phy_2;						/* if (shm_phy_type == PHY_TYPE_B) */
		orx	0, 8, [SHM_LAST_RX_ANTENNA], SPR_Ext_IHR_Data, GP_REG6;			/* GP_REG6 = (((shm_last_rx_antenna<<8) | (shm_last_rx_antenna>>8)) & 0x100) | (SPR_Ext_IHR_Data & ~0x100) */
		jext	COND_TRUE, B_phy_2;					
	no_antenna_update:;
		xor	SPR_Ext_IHR_Data, 0x080, GP_REG6;					/* GP_REG6 = SPR_Ext_IHR_Data ^ 0x80 */
		je	[SHM_PHYTYPE], 0x001, B_phy_2;						/* if (shm_phy_type == PHY_TYPE_B) */
		xor	SPR_Ext_IHR_Data, 0x100, GP_REG6;					/* GP_REG6 = SPR_Ext_IHR_Data ^ 0x100 */
	B_phy_2:;
		call	lr0, write_phy_reg;					
		mov	0, ANTENNA_DIVERSITY_CTR;						/* antenna_diversity_counter = 0x0000 */		
	end_antenna_diversity_helper:;
		ret	lr1, lr1;

// ***********************************************************************************************
// FUNCTION:	gphy_classify_control_with_arg
// PURPOSE:	Manages classify control for G PHY devices.
//
	gphy_classify_control_with_arg:;
		jne	[SHM_PHYTYPE], 0x002, end_gphy_classify_control_with_arg;	/* if (shm_phy_type != PHY_TYPE_G) */				
		mov	0x0802, GP_REG5;						/* GP_REG5 = GPHY_CLASSIFY_CTRL */				
		call	lr0, write_phy_reg;					
	end_gphy_classify_control_with_arg:;
		ret	lr1, lr1;

// ***********************************************************************************************
// FUNCTION:	check_gphy_sym_war	
// PURPOSE:	Checks for workaround.
//
	check_gphy_sym_war:;
		jzx	0, 1, [SHM_HF_LO], 0x000, end_check_gphy_sym_war;	/* if (!(SHM_HF_LO & MHF_SYMWAR)) */		
		je	[SHM_PHYTYPE], 0x000, end_check_gphy_sym_war;		/* if (shm_phy_type == PHY_TYPE_A) */	
		jnzx	1, 0, RX_PHY_ENCODING, 0x000, end_check_gphy_sym_war;	/* if (rx_phy_encoding & 0x03) */			
		jne	RX_TYPE, 0x001, end_check_gphy_sym_war;			/* if (RX_TYPE != 0x01) */	
		srx	7, 0, [RX_FRAME_PLCP_0,off1], 0x000, GP_REG5;		/* GP_REG5 = (mem[rx_frame_offs + FR_OFFS_PLCP_0]) & 0xff */	
		jle	GP_REG5, 0x014, end_check_gphy_sym_war;			/* if (GP_REG5 <=u 0x14) */	
		jne	[RX_FRAME_PLCP_1,off1], 0x050, end_check_gphy_sym_war;	/* if (mem[rx_frame_offs + FR_OFFS_PLCP_1] != 0x50) */	
		mov	0x0001, GPHY_SYM_WAR_FLAG;				
		orx	0, 4, 0x001, SPR_IFS_CTL, SPR_IFS_CTL;			/* SPR_IFS_control = SPR_IFS_control | 0x10 */	
	end_check_gphy_sym_war:;
		ret	lr1, lr1;

// ***********************************************************************************************
// FUNCTION:	bg_noise_sample	
// PURPOSE:	Performs a noise measurement on the channel.
//
	bg_noise_sample:
		jzx	0, 4, SPR_MAC_CMD, 0x000, stop_bg_noise_sample;			/* if (!(SPR_MAC_Command & MCMD_BG_NOISE)) */			
		jnzx	0, 3, GLOBAL_FLAGS_REG3, 0x000, bg_noise_inprogress;		/* if (GLOBAL_FLAGS_REG3 & BG_NOISE_INPROGR) */	
		orx	0, 3, 0x001, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 = BG_NOISE_INPROGR | (GLOBAL_FLAGS_REG3 & ~BG_NOISE_INPROGR) */			
		or	SPR_TSF_WORD0, 0x000, 0x000;					
		or	SPR_TSF_WORD1, 0x000, [SHM_BGN_START_TSF1];			/* mem[SHM_BGN_START_TSF1] = SPR_TSF_word_1 */
	bg_noise_inprogress:;
		or	SPR_TSF_WORD0, 0x000, 0x000;					/* 0x00 = SPR_TSF_word_0 */
		sub	SPR_TSF_WORD1, [SHM_BGN_START_TSF1], GP_REG8;			/* GP_REG8 = SPR_TSF_word_1 - mem[SHM_BGN_START_TSF1] */			
		mov	0x0008, GP_REG5;				
		call	lr0, sel_phy_reg;					
		srx	7, 0, SPR_Ext_IHR_Data, 0x000, [SHM_JSSIAUX];			/* shm_JSSI_AUX = (SPR_Ext_IHR_Data) & 0xff */
		orx	0, 10, GLOBAL_FLAGS_REG1, 0x05F, GP_REG5;			/* GP_REG5 = (((GLOBAL_FLAGS_REG1<<10) | (GLOBAL_FLAGS_REG1>>6)) & 0x400) | 0x5f */	
		call	lr0, sel_phy_reg;					
		orx	7, 8, SPR_Ext_IHR_Data, [SHM_JSSIAUX], [SHM_JSSIAUX];		/* shm_JSSI_AUX = (SPR_Ext_IHR_Data << 8) | shm_JSSI_AUX */
		mov	0x0027, GP_REG5;						/* GP_REG5 = BPHY_JSSI */
		mov	0x0044, SPR_BASE5;				
		mov	0x0000, GP_REG6;				
	loop_on_JSSI:;
		add	GP_REG6, 0x001, GP_REG6;					/* GP_REG6 = GP_REG6 + 0x001 */
		add	SPR_TSF_WORD0, 0x002, GP_REG7;					/* GP_REG7 = SPR_TSF_word_0 + 0x02 */
	wait_for_time_to_be_elapsed_2us:;
		jext	COND_TX_NOW, stop_bg_noise_sample;						
		jzx	0, 11, SPR_IFS_STAT, 0x000, no_frame_to_transmit;		/* if (!(SPR_IFS_stat & 0x800)) */
		jl	GP_REG8, 0x002, stop_bg_noise_sample;				/* if (GP_REG8 <u 0x02) */
	no_frame_to_transmit:;
		jne	GP_REG7, SPR_TSF_WORD0, wait_for_time_to_be_elapsed_2us;	/* if (GP_REG7 != SPR_TSF_word_0) */
		call	lr0, sel_phy_reg;					
		orx	8, 0, SPR_Ext_IHR_Data, [0x00,off5], [0x00,off5];		/* mem[offs5 + 0x0] = (SPR_Ext_IHR_Data & 0x1ff) | (mem[offs5 + 0x0] & ~0x1ff) */
		jne	[SHM_PHYTYPE], 0x000, not_A_phy;				/* if (shm_phy_type != PHY_TYPE_A) */
		jnzx	0, 8, SPR_Ext_IHR_Data, 0x000, rise_bg_noise_complete_irq;	/* if (SPR_Ext_IHR_Data & 0x100) */		
		jext	COND_TRUE, A_phy;					
	not_A_phy:;
		rr	[0x00,off5], 0x008, [0x00,off5];				/* mem[offs5 + 0x0] = (mem[offs5 + 0x0] >> 0x08) | (mem[offs5 + 0x0] << (16 - 0x08)) */		
		xor	SPR_BASE5, 0x001, SPR_BASE5;				
	A_phy:;
		jl	GP_REG6, 0x004, loop_on_JSSI;					/* if (GP_REG6 <u 0x04) */
		jge	GP_REG8, 0x002, rise_bg_noise_complete_irq;			/* if (GP_REG8 >=u 0x02) */
		add	SPR_TSF_WORD0, 0x018, GP_REG7;					/* GP_REG7 = SPR_TSF_word_0 + 0x18 */
	wait_for_time_to_be_elapsed_24us:;
		jext	COND_TX_NOW, stop_bg_noise_sample;				/* if (CR2 & 0x0001) */
		jnzx	0, 11, SPR_IFS_STAT, 0x000, stop_bg_noise_sample;		/* if (SPR_IFS_stat & 0x800) */
		jne	GP_REG7, SPR_TSF_WORD0, wait_for_time_to_be_elapsed_24us;	/* if (GP_REG7 != SPR_TSF_word_0) */	
	rise_bg_noise_complete_irq:;
		mov	0x0010, SPR_MAC_CMD;				
		mov	0x0004, SPR_MAC_IRQHI;						/* SPR_MAC_Interrupt_Status_High = MI_BG_NOISE */
		orx	0, 3, 0x000, GLOBAL_FLAGS_REG3, GLOBAL_FLAGS_REG3;		/* GLOBAL_FLAGS_REG3 = GLOBAL_FLAGS_REG3 & ~BG_NOISE_INPROGR */					
	stop_bg_noise_sample:;
		ret	lr3, lr2;

// ***********************************************************************************************
// FUNCTION:	update_wme_params	
// PURPOSE:	Updates queue related contention informations.
//
	update_wme_params:;	
		or	SPR_IFS_0x0e, 0x000, GP_REG1;				
		mov	SHM_EDCFQCUR, SPR_BASE4;				
		mov	SHM_TXHEADER, SPR_BASE5;				
		mov	0x0004, GP_REG5;
		je	[SHM_EDCFQ_CWMIN,off4], DEFAULT_MIN_CW, cw_max_min_ok;
		mov	DEFAULT_MAX_CW, [SHM_EDCFQ_CWMAX,off4];
		mov	DEFAULT_MIN_CW, [SHM_EDCFQ_CWMIN,off4];
	cw_max_min_ok:
		jne     GP_REG6, 0x001, update_wme_into_rx_wme8;
		orx     0, 9, 0x001, [SHM_EDCFQ_STATUS,off4], [SHM_EDCFQ_STATUS,off4];	/* update edcf status */
                or      [SHM_EDCFQ_CWCUR,off4], 0x000, GP_REG0;				/* GP_REG0 = cwcur */
		and     SPR_TSF_Random, GP_REG0, GP_REG2;				/* GP_REG2 = GP_REG0 & Random */
                or      GP_REG2, 0x000, [SHM_EDCFQ_BSLOTS,off4];			/* bslots = GP_REG2 */
                add     GP_REG2, [SHM_EDCFQ_AIFS,off4], [SHM_EDCFQ_REGGAP,off4];	/* reggap = GP_REG2 + aifs */
	update_wme_into_rx_wme8:;
                or      [SHM_EDCFQ_AIFS,off4], 0x000, GP_REG2;				/* GP_REG2 = aifs */
                sub     GP_REG1, GP_REG2, GP_REG9;					/* GP_REG9 = GP_REG1 - GP_REG2 */
                jles    GP_REG9, 0x000, update_wme_end;					/* GP_REG9 <= 0 ? update_wme_end (we need at least an aifs to be elapsed) */
                sub     [SHM_EDCFQ_BSLOTS,off4], GP_REG9, [SHM_EDCFQ_BSLOTS,off4];	/* bslots = bslots - (elapsed_time - aifs) */
                jges    [SHM_EDCFQ_BSLOTS,off4], 0x000, update_bslots;			/* update bslots if greater then 0 */
                mov	0, [SHM_EDCFQ_BSLOTS,off4];					/* bslots can be at least 0 */
	update_bslots:;
                or      [SHM_EDCFQ_BSLOTS,off4], 0x000, GP_REG9;			/* GP_REG9 = bslots */
                add     [SHM_EDCFQ_AIFS,off4], GP_REG9, [SHM_EDCFQ_REGGAP,off4];	/* reggap = bslots + aifs */	
	update_wme_end:;
		or	GP_REG5, 0x000, GP_REG5;
		ret	lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	update_wme_params_availability
// PURPOSE:	Updates queue related transmission informations.
//
	update_wme_params_availability:
		mov	SHM_EDCFQCUR, SPR_BASE4;						/* BASE4 points to the start of queue 1 params */
		mov	SHM_TXHEADER, GP_REG8;							/* GP_REG8 = queue 1 frame header */
		or      CUR_CONTENTION_WIN, 0x000, [SHM_EDCFQ_CWCUR,off4];			/* mem[offs4_edcf_entry.cwcur] = cur_contention_win */	
		orx	3, 0, SHORT_RETRIES, [SHM_EDCFQ_STATUS,off4], [SHM_EDCFQ_STATUS,off4];	/* mem[offs4 + 0x7] := (short_retries & 0xf) | (mem[offs4 + 0x7] & ~0xf) */
		orx	3, 3, LONG_RETRIES, [SHM_EDCFQ_STATUS,off4], [SHM_EDCFQ_STATUS,off4];	/* mem[offs4 + 0x7] := ((long_retries<<3 & 0x78) | (mem[offs4 + 0x7] & ~0x78) */
		or	SPR_TXE0_FIFO_RDY, 0x000, GP_REG0;
		and	GP_REG0, 0x00F, GP_REG0;
		or	GP_REG0, 0x000, [SHM_FIFO_RDY];		
		je	GP_REG0, 0x000, no_frame_to_send;
		or	[SHM_EDCFQ_CWCUR,off4], 0x000, CUR_CONTENTION_WIN;			/* cur_contention_win = mem[offs4_edcf_entry.cwcur] */
		or	[SHM_EDCFQ_CWMIN,off4], 0x000, MIN_CONTENTION_WIN;			/* min_contention_win = mem[offs4_edcf_entry.cwmin] */
		or	[SHM_EDCFQ_CWMAX,off4], 0x000, MAX_CONTENTION_WIN;			/* max_contention_win = mem[offs4_edcf_entry.cwmax] */
		orx	3, 0, [SHM_EDCFQ_STATUS,off4], SHORT_RETRIES, SHORT_RETRIES;		/* short_retries update */
		orx	3, 3, [SHM_EDCFQ_STATUS,off4], LONG_RETRIES, LONG_RETRIES;		/* long_retries update */
	no_frame_to_send:
		ret	lr0, lr0;

// ***********************************************************************************************
// FUNCTION:	set_backoff_time
// PURPOSE:	Updates backoff time for contention operation.
//
	set_backoff_time:;
		srx	2, 8, [SHM_TXFCUR], 0x000, GP_REG5;				/* GP_REG5 = ((SHM_TXFCUR) >> 8) & 0x7 */			
		or	SHM_EDCFQCUR, 0x000, SPR_BASE4;					/* SPR_BASE4 = shm_edcf1_paramptr */
		and	SPR_TSF_Random, CUR_CONTENTION_WIN, GP_REG5;			/* GP_REG5 = SPR_TSF_Random & CUR_CONTENTION_WIN */		
		or	GP_REG5, 0x000, [SHM_EDCFQ_BSLOTS,off4];			/* mem[offs4_edcf_entry.bslots] = GP_REG5 */
		add	[SHM_EDCFQ_AIFS,off4], GP_REG5, [SHM_EDCFQ_REGGAP,off4];	/* mem[offs4_edcf_entry.reggap] = mem[offs4_edcf_entry.aifs] + GP_REG5 */
		or	[SHM_EDCFQ_REGGAP,off4], 0x000, GP_REG5;			/* GP_REG5 = mem[offs4_edcf_entry.reggap] */
		jnzx	0, 11, SPR_IFS_STAT, 0x000, need_more_time_to_elapse;		/* if (SPR_IFS_stat & 0x800) -- if time was elapsed */
		or	SPR_IFS_0x0e, 0x000, GP_REG1;					/* GP_REG1 = SPR_IFS_0x0e (elapsed time) */
		jl	GP_REG5, GP_REG1, need_more_time_to_elapse;			/* if (GP_REG5 <u GP_REG1) -- If reggap was already elapsed */	
		sub	GP_REG5, GP_REG1, GP_REG0;					/* GP_REG0 = GP_REG5 - GP_REG1 */	
		or	GP_REG0, 0x000, SPR_IFS_BKOFFDELAY;				/* SPR_IFS_BKOFFDELAY = GP_REG0 */	
		jext	COND_TRUE, end_backoff_time_update;					
	need_more_time_to_elapse:;
		or	GP_REG5, 0x000, SPR_IFS_BKOFFDELAY;				/* SPR_IFS_BKOFFDELAY = GP_REG5 */
	end_backoff_time_update:;
		or	CUR_CONTENTION_WIN, 0x000, [SHM_EDCFQ_CWCUR,off4];		/* mem[offs4_edcf_entry.cwcur] = CUR_CONTENTION_WINDOW */
		ret	lr1, lr1;

// ***********************************************************************************************
// FUNCTION:	mod_txe0_control_for_edcf	
// PURPOSE:	Modifies NEXT_TXE0_CTL according to EDCF needs.
//
	mod_txe0_control_for_edcf:;
		jnext	0x28, update_txe0_control_for_edcf;						
		orx	1, 1, 0x000, NEXT_TXE0_CTL, NEXT_TXE0_CTL;		/* NEXT_TXE0_CTL = NEXT_TXE0_CTL & ~0x6 */			
		jext	COND_TRUE, end_txe0_control_for_edcf;					
	update_txe0_control_for_edcf:;
		orx	0, 9, 0x000, GLOBAL_FLAGS_REG1, GLOBAL_FLAGS_REG1;	/* GLOBAL_FLAGS_REG1 = GLOBAL_FLAGS_REG1 & ~0x200 */				
		or	NEXT_TXE0_CTL, 0x014, NEXT_TXE0_CTL;			/* NEXT_TXE0_CTL = NEXT_TXE0_CTL | 0x14 */		
	end_txe0_control_for_edcf:;
		ret	lr0, lr0;
		@000	@000, @000, @000;

#include "initvals.asm"
