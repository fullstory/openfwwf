/*
 *  BCM43xx device microcode
 *  Initial values
 *   For Wireless-Core Revision 5
 *
 *  Copyright (C) 2009		University of Brescia
 *
 *  Copyright (C) 2008		Michael Buesch <mb@bu3sch.de>
 *  Copyright (C) 2008, 2009	Lorenzo Nava <navalorenx@gmail.com>
 *				Francesco Gringoli <francesco.gringoli@ing.unibs.it>						 
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

#include "initvals.inc"
#include "shm.inc"
#include "myreg.inc"


.initvals(b0g0initvals5)

	/* write 0x5 @ 0x0016 (core revision) */
	//mmio32 0x3010005, MMIO_SHM_CONTROL
	//mmio32 0x0050000, MMIO_SHM_DATA

	/* first mac command */
	mmio32 0x4, MMIO_MACCMD

	/* Initialize the interrupts */
	mmio32 0, MMIO_GEN_IRQ_REASON
	mmio32 0, MMIO_GEN_IRQ_MASK

	/* ACK Template */
	mmio32 0, MMIO_RAM_CONTROL
	mmio32 0x70040A, MMIO_RAM_DATA
	mmio32 0xD4BEEF, MMIO_RAM_DATA
	mmio32 0xFF000005, MMIO_RAM_DATA
	mmio32 0xFF02FF01, MMIO_RAM_DATA

	/* Initialize PHY */
	mmio32 0x01000000, MMIO_IPFT0
        mmio16 0, MMIO_PHY0

	/* Initialize PSM */
        mmio16 0, MMIO_PSM_BRC
        mmio16 0xE3F9, MMIO_PSM_BRED0
        mmio16 0xFDAF, MMIO_PSM_BRPO0
        mmio16 0xFFFF, MMIO_PSM_BRCL0
        mmio16 0x0000, MMIO_PSM_BRCL0
        mmio16 0x0000, MMIO_PSM_BRCL1
        mmio16 0x1ACF, MMIO_PSM_BRED2
        mmio16 0x0000, MMIO_PSM_BRCL2
        mmio16 0x0000, MMIO_PSM_BRWK2
        mmio16 0x00C7, MMIO_PSM_BRED3
        mmio16 0xFFFF, MMIO_PSM_BRPO3
        mmio16 0xFFFF, MMIO_PSM_BRCL3

	/* Initialize RX engine */
	mmio16 1, MMIO_RXE_FIFOCTL
        mmio16 0, MMIO_RXE_FIFOCTL
        mmio16 0x14, 0x40C
        mmio16 0, MMIO_RXE_FIFOCTL

	/* where is initialized MMIO_RXE_RXCOPYLEN ?? */
	mmio16 SHM_RXHEADER, MMIO_RXE_RXMEM

	/* Initialize TME Mask */
	mmio16 0xFFFF, 0x580
	mmio16 0xFFFF, 0x582
	mmio16 0xFFFF, 0x584
	mmio16 0xFFFF, 0x586
	mmio16 0xFFFF, 0x588
	mmio16 0xFFF0, 0x59C

	/* Transmit Control Init */
	mmio16 0x8000, MMIO_TCTL_FIFOCMD
        mmio16 0x0E06, MMIO_TCTL_FIFODEF
        mmio16 0x8000, MMIO_TCTL_FIFOCMD

        mmio16 0x8100, MMIO_TCTL_FIFOCMD
        mmio16 0x1B0F, MMIO_TCTL_FIFODEF
        mmio16 0x8100, MMIO_TCTL_FIFOCMD

        mmio16 0x8200, MMIO_TCTL_FIFOCMD
        mmio16 0x251C, MMIO_TCTL_FIFODEF
        mmio16 0x8200, MMIO_TCTL_FIFOCMD

        mmio16 0x8300, MMIO_TCTL_FIFOCMD
        mmio16 0x2D26, MMIO_TCTL_FIFODEF
        mmio16 0x8300, MMIO_TCTL_FIFOCMD

        mmio16 0x8400, MMIO_TCTL_FIFOCMD
        mmio16 0x3A2E, MMIO_TCTL_FIFODEF
        mmio16 0x8400, MMIO_TCTL_FIFOCMD

        mmio16 0x8500, MMIO_TCTL_FIFOCMD
        mmio16 0x3B3B, MMIO_TCTL_FIFODEF
        mmio16 0x8500, MMIO_TCTL_FIFOCMD

	 /* TSF init */
        mmio16 1, MMIO_TSF_CFP_PRETBTT
        mmio16 0xA2E9, 0x62E
        mmio16 0xB, 0x630
        mmio16 0x8004, 0x600

        /* Interframe space init */
        mmio16 0xB, MMIO_IFSCTL

	// **********************************************************************
	// **********************************************************************
	/* SHM Values */

	// *****************************************************
	// BLOCK1, starts @ 0x0010 = 0x0004 * 4
	// 0x0010: [(00 00) (00 00)] [(00 80) (00 00)] [(00 47) (00 47)]
        // 00x01c: [(00 00) (00 64)] [(09 30) (00 00)]
	// 0x0010: 802.11 Slot Time = 0 (SHM_SLOTT), used by ucode not by b43?
	// 0x0012: DTIM Period = 0 (SHM_DTIMPER), used by ucode not by b43?
	// 0x0014: Not used by ucode or b43
	// 0x0016: 802.11 Core Revision (SHM_WLCOREREV), should take the same value assigned above? used by b43
	// 0x0018: Beacon 0 Template Length (SHM_BTL0) = 0x47, used by ucode, not by b43 (sure? check with AP mode)
	// 0x001a: Beacon 1 Template Length (SHM_BTL1) = 0x47, used by ucode, not by b43 (sure? check with AP mode)
	// 0x001c: Beacon Transmit TSF Offset (SHM_BTSFOFF) = 0, used by ucode, not by b43 (sure? check with AP mode)
	// 0x001e: TIM Position (SHM_TIMBPOS) = 100, used by ucode, not by b43 (sure? check with AP mode)
	// 0x0020: MAXPDULEN (SHM_MAXPDULEN) = 0x930 = 2352, used by ucode, not by b43
	// 0x0022: ACK/CTS PHY control word (SHM_ACKCTSPHYCTL) = 0, used by ucode and b43
	mmio32 0x03010004, MMIO_SHM_CONTROL
	mmio32 0x00000000, MMIO_SHM_DATA 
	mmio32 0x00000080, MMIO_SHM_DATA 
	mmio32 0x00470047, MMIO_SHM_DATA
	mmio32 0x00640000, MMIO_SHM_DATA
	mmio32 0x00000930, MMIO_SHM_DATA
 
	// *****************************************************
	// BLOCK2, starts @ 0x0034 = 0x000D * 4
	// 0x0034: [(00 02) (00 02)] [(00 01) (00 04)] [(00 1e) (00 00)]
	// 0x0034: RX Padding Data Offset (SHM_RXPADOFF) = 2,
	//		sometime its value is copied to [0xA90(=0x548*2)]
	// 0x0036: ?? = 2, not used by ucode or b43
	// 0x0038: Offset To Duration (SHM_TBL_OFF2DUR) = 1,
	//		useb by ucode in rx_beacon_probe_resp to obtain the frame duration from
	//		second level rate table to refresh the receive time and synhronize
	// 0x003A: ?? = 4, not used by ucode or b43
	// 0x003C: Default IV location = 1e, not used by ucode or b43
	// 0x003E: Number of soft RX transmitter addresses (max 8) = 0, not used by ucode or b43
	mmio32 0x0301000D, MMIO_SHM_CONTROL
	mmio32 0x00020002, MMIO_SHM_DATA 
	mmio32 0x00040001, MMIO_SHM_DATA 
	mmio32 0x0000001E, MMIO_SHM_DATA 

	// *****************************************************
	// BLOCK3, starts @ 0x0044 = 0x0011 * 4
	// 0x0044: [(00 64) (00 64)] [(00 0E) (00 47)] [(28 00) (00 00)]
	// 0x0044: Short Frame Fallback Retry Limit (SHM_SFFBLIM) (beacon related??) = 0x64, used by b43 and by ucode
	// 0x0046: Long Frame Fallback Retry Limit (SHM_LFFBLIM) (beacon related??) = 0x64, used by b43 not by ucode as RTS/CTS not implemented
	// 0x0048: Probe Response SSID Length (SHM_PRSSIDLEN) = 0x08, not used by ucode, not used by b43 (check if ap or ad-hoc use them)
	// 0x004A: Probe Response Template Length (SHM_PRTLEN) = 0x47, not used by ucode, not used by b43 (check if ap or ad-hoc use them)
	// 0x004C: NOSLPZNAT DTIM (SHM_NOSLPZNATDTIM) = 0x2800, used by ucode, not used by b43 (check if ap or ad-hoc use them)
	// 0x004E: OFDM/CCK delta in CCK power boost mode = 0x0000, not used by ucode, not used by b43
	mmio32 0x03010011, MMIO_SHM_CONTROL
	mmio32 0x00640064, MMIO_SHM_DATA
	mmio32 0x0047000E, MMIO_SHM_DATA
	mmio32 0x00002800, MMIO_SHM_DATA

	// *****************************************************
	// BLOCK4, starts @ 0x0054 = 0x0015 * 4
	// 0x0044: [(00 00) (05 82)] [(FF FF) (FF FF)] [(00 0A) (00 00)]
	// 0x0054: Beacon PHY TX control word (SHM_BEACPHYCTL), used by ucode, used by b43
	// 0x0056: Key table pointer (SHM_KTP), not used by ucode, used by b43
	// 0x0058: TSSI for the last 4 CCK frames lo (SHM_TSSI_CCK_LO),   used with value below by tx_frame_now... , used by b43
	// 0x005A: TSSI for the last 4 CCK frames high (SHM_TSSI_CCK_HI), ... through off5 (SPR_BASE5)             , used by b43
	// 0x005C: Antenna swap threshold (SHM_ANTSWAP), used by ucode, not used by b43
	// 0x005E: Hostflags for ucode options (low) (SHM_HF_LO), used by ucode, used by b43
	mmio32 0x03010015, MMIO_SHM_CONTROL
	mmio32 0x05820000, MMIO_SHM_DATA
	mmio32 0xFFFFFFFF, MMIO_SHM_DATA
	mmio32 0x0000000A, MMIO_SHM_DATA

	// *****************************************************
	// BLOCK5, starts @ 0x0074 = 0x001D * 4
	// 0x0074: [(27 10) (00 00)]
	// 0x0074: Probe Response max time (SHM_PRMAXTIME), not used by ucode, used by b43 (related to offloading?)
	// 0x0076: ? no mean?
	mmio32 0x0301001D, MMIO_SHM_CONTROL
	mmio32 0x00002710, MMIO_SHM_DATA        
	
	// *****************************************************
	// BLOCK6, starts @ 0x0080 = 0x0020 * 4
	// 0x0080: [(00 06) (27 10)]
	// 0x0080: Maximum number of frames in a burst (SHM_MAXBFRAMES), not used by ucode, not used by b43 (Turbo?)
	// 0x0082: ? no mean?
	mmio32 0x03010020, MMIO_SHM_CONTROL
	mmio32 0x27100006, MMIO_SHM_DATA 

	// *****************************************************
	// BLOCK7, starts @ 0x008C = 0x0023 * 4
	// 0x008C: [(00 00) (02 07)]
	// 0x008C: Measure JSSI AUX (SHM_JSSIAUX), used by ucode, not used by b43
	// 0x008E: ? no mean?
	mmio32 0x03010023, MMIO_SHM_CONTROL
	mmio32 0x02070000, MMIO_SHM_DATA 
	
	// *****************************************************
	// BLOCK8, starts @ 0x0094 = 0x0025 * 4
	// 0x0094: [(00 00) (00 32)] [(0D 09) (08 0A)] [(01 0D) (00 00)]
	// 0x0094: pre-wakeup for synth PU in us (SHM_SPUWKUP), not used by ucode, used by b43
	// 0x0096: pre-TBTT in us (SHM_PRETBTT), not used by ucode, used by b43
	// 0x0098: TX FIFO size for FIFO 0 (low) and 1 (high) (SHM_TXFIFO_SIZE01), not used by ucode, not used by b43
	// 0x009A: TX FIFO size for FIFO 2 (low) and 3 (high) (SHM_TXFIFO_SIZE23), not used by ucode, not used by b43
	// 0x009C: TX FIFO size for FIFO 4 (low) and 5 (high) (SHM_TXFIFO_SIZE45), not used by ucode, not used by b43
	// 0x009E: TX FIFO size for FIFO 6 (low) and 7 (high) (SHM_TXFIFO_SIZE67), not used by ucode, not used by b43
	mmio32 0x03010025, MMIO_SHM_CONTROL
	mmio32 0x00320000, MMIO_SHM_DATA
	mmio32 0x080A0D09, MMIO_SHM_DATA 
	mmio32 0x0000010D, MMIO_SHM_DATA 
 
	// *****************************************************
	// BLOCK9, starts @ 0x00A4 = 0x0029 * 4
	// 0x00A4: ?? no mean? not used
	// 0x00A6: Value for the G-PHY classify control register (SHM_GCLASSCTL), used by ucode, not used by b43
	// 0x00A8: Last bcast/mcast frame ID (SHM_MCASTCOOKIE), used by ucode, not used by b43
	// 0x00AA: ?? no mean? not used
	mmio32 0x03010029, MMIO_SHM_CONTROL
	mmio32 0x013F0000, MMIO_SHM_DATA 
	mmio32 0x0000FFFF, MMIO_SHM_DATA
 
	// *****************************************************
	// BLOCK10, starts @ 0x0160 = 0x0058 * 4
	// 0x0160: Probe Response SSID (SHM_PRSSID), not used by ucode, not used by b43
	// 0x0162: ?? no mean?
	// 0x0164: (MMIO_SHM_DATA), not used by ucode, not used by b43
	// 0x0166: (MMIO_SHM_DATA_UNALIGNED), not used by ucode, not used by b43
	// 0x0168: ?? no mean?
	// 0x016A: ?? no mean?
	// 0x016C: ?? no mean?
	// 0x016E: (SHM_FIFO_RDY), used by ucode, not used by b43
	mmio32 0x03010058, MMIO_SHM_CONTROL
	mmio32 0x4D435242, MMIO_SHM_DATA 
	mmio32 0x5345545F, MMIO_SHM_DATA
	mmio32 0x53535F54, MMIO_SHM_DATA
	mmio32 0x00004449, MMIO_SHM_DATA

	/* Rate Tables: each 32-bit word is made of a couple of pointers to upper shm tables */

	// OFDM direct (Firmware access at 0x00E0 = 0x0070 * 2, real address is 0x01c0)
	// 32 bytes up to 0x0078 - 1
	mmio32 0x03010070, MMIO_SHM_CONTROL

	mmio32 0x032E032E, MMIO_SHM_DATA
	mmio32 0x032E032E, MMIO_SHM_DATA
	mmio32 0x032E032E, MMIO_SHM_DATA
	mmio32 0x032E032E, MMIO_SHM_DATA
	mmio32 0x0356036A, MMIO_SHM_DATA	// high: addr for 24Mb/s ACK, low: addr for 48Mb/s ACK
	mmio32 0x032E0342, MMIO_SHM_DATA	// high: addr for 6Mb/s ACK, low: addr for 12Mb/s ACK
	mmio32 0x03600374, MMIO_SHM_DATA	// high: addr for 36Mb/s ACK, low: addr for 54Mb/s ACK
	mmio32 0x0338034C, MMIO_SHM_DATA	// high: addr for 9Mb/s ACK, low: addr for 18Mb/s ACK

	// CCK direct (Firmware access at 0x100 = 0x0080 * 2, real address is 0x0200)
	// 32 bytes up to 0x0088 - 1
	mmio32 0x03010080, MMIO_SHM_CONTROL

	mmio32 0x037E037E, MMIO_SHM_DATA
	mmio32 0x037E037E, MMIO_SHM_DATA
	mmio32 0x037E0389, MMIO_SHM_DATA	//(high: -- low: addr for 2Mb/s ACK)
	mmio32 0x0394037E, MMIO_SHM_DATA	//(high: addr for 5.5Mb/s ACK low: --)
	mmio32 0x037E037E, MMIO_SHM_DATA
	mmio32 0x037E037E, MMIO_SHM_DATA	//(high: -- low: addr for 1Mb/s ACK)
	mmio32 0x037E037E, MMIO_SHM_DATA
	mmio32 0x037E039F, MMIO_SHM_DATA	//(high: -- low: addr for 11Mb/s ACK)

	/* Contention Window */

        // firmware uses just one contention window (Firmware access at 0x0130 = 0x098 * 2, real address is 0x0260)
	mmio32 0x03010098, MMIO_SHM_CONTROL

	mmio32 0x001F0000, MMIO_SHM_DATA
	mmio32 0x001F03FF, MMIO_SHM_DATA
	mmio32 0x00000001, MMIO_SHM_DATA
	mmio32 0x00000001, MMIO_SHM_DATA

	// Actual rate tables (Firmware access from 0x32E = 0x197 * 2, real address is 0x65C = 0x197 * 4)
	mmio32 0x03010197, MMIO_SHM_CONTROL

	mmio32 0x01CB0020, MMIO_SHM_DATA	// 0x32E high: encoding for 6Mb/s ACK, low --
	mmio32 0x00000000, MMIO_SHM_DATA
	mmio32 0x08AB0000, MMIO_SHM_DATA
	mmio32 0x04100000, MMIO_SHM_DATA
	mmio32 0x00000084, MMIO_SHM_DATA

	mmio32 0x01CF0014, MMIO_SHM_DATA	// 0x338 high: encoding for 9Mb/s ACK, low --
	mmio32 0x00000002, MMIO_SHM_DATA
	mmio32 0x08AF0000, MMIO_SHM_DATA
	mmio32 0x04100002, MMIO_SHM_DATA
	mmio32 0x00000064, MMIO_SHM_DATA

	mmio32 0x01CA0010, MMIO_SHM_DATA	// 0x342 high: encoding for 12Mb/s ACK, low --
	mmio32 0x00000002, MMIO_SHM_DATA
	mmio32 0x08AA0000, MMIO_SHM_DATA
	mmio32 0x04100002, MMIO_SHM_DATA
	mmio32 0x00000054, MMIO_SHM_DATA

	mmio32 0x01CE0008, MMIO_SHM_DATA	// 0x34C high: encoding for 18Mb/s ACK, low --
	mmio32 0x00000000, MMIO_SHM_DATA
	mmio32 0x08AE0000, MMIO_SHM_DATA
	mmio32 0x04100000, MMIO_SHM_DATA
	mmio32 0x00000044, MMIO_SHM_DATA

	mmio32 0x01C90008, MMIO_SHM_DATA	// 0x356 high: encoding for 24Mb/s ACK, low --
	mmio32 0x00000002, MMIO_SHM_DATA
	mmio32 0x08A90000, MMIO_SHM_DATA
	mmio32 0x04100002, MMIO_SHM_DATA
	mmio32 0x0000003C, MMIO_SHM_DATA

	mmio32 0x01CD0004, MMIO_SHM_DATA	// 0x360 high: encoding for 36Mb/s ACK, low --
	mmio32 0x00000000, MMIO_SHM_DATA
	mmio32 0x08AD0000, MMIO_SHM_DATA
	mmio32 0x04100000, MMIO_SHM_DATA
	mmio32 0x00000034, MMIO_SHM_DATA

	mmio32 0x01C80004, MMIO_SHM_DATA	// 0x36A high: encoding for 48Mb/s ACK, low --
	mmio32 0x00000000, MMIO_SHM_DATA
	mmio32 0x08A80000, MMIO_SHM_DATA
	mmio32 0x04100000, MMIO_SHM_DATA
	mmio32 0x00000030, MMIO_SHM_DATA

	mmio32 0x01CC0000, MMIO_SHM_DATA	// 0x374 high: encoding for 54Mb/s ACK, low --
	mmio32 0x00000002, MMIO_SHM_DATA
	mmio32 0x08AC0000, MMIO_SHM_DATA
	mmio32 0x04100002, MMIO_SHM_DATA
	mmio32 0x00000030, MMIO_SHM_DATA

	mmio32 0x040A00C0, MMIO_SHM_DATA	// 0x37E high: enconding for 1Mb/s ACK, low: --
	mmio32 0x00000070, MMIO_SHM_DATA	// high: -- low: duration for 1Mb/s ACK
	mmio32 0x040A013A, MMIO_SHM_DATA	// high: -- low: NAV for 1Mb/s ACK (314us = 14*8 + 192 + 10)
	mmio32 0xC02C0228, MMIO_SHM_DATA
	mmio32 0x000002F2, MMIO_SHM_DATA

	mmio32 0x00600000, MMIO_SHM_DATA	// 0x388
	mmio32 0x00380414, MMIO_SHM_DATA	// high: duration for for 2Mb/s ACK low: encoding for 2Mb/s ACK
	mmio32 0x01020000, MMIO_SHM_DATA	// high: NAV for 2Mb/s ACK (258us = 14*8/2 + 192 + 10) low: --
	mmio32 0x01140414, MMIO_SHM_DATA
	mmio32 0x01DEC02C, MMIO_SHM_DATA

	// we have 2 bytes skipped!

	// Other tables (Firmware access from 0x394 = 0x1CA * 2, real address is 0x728 = 0x1CA * 4)
	mmio32 0x030101CA, MMIO_SHM_CONTROL

	mmio32 0x04370022, MMIO_SHM_DATA	// high: encoding for 5.5Mb/s ACK low: --
	mmio32 0x00000015, MMIO_SHM_DATA	// high: -- low: duration for 5.5Mb/s ACK
	mmio32 0x043700DF, MMIO_SHM_DATA	// high: -- low: NAV for 5.5Mb/s ACK (223us = 14*8/5.5 + 192 + 10 ceiled)
	mmio32 0xC02C0065, MMIO_SHM_DATA
	mmio32 0x0000012E, MMIO_SHM_DATA
	mmio32 0x00110000, MMIO_SHM_DATA
	mmio32 0x000B846E, MMIO_SHM_DATA	// high: duration for 11Mb/s ACK low: encoding for 11Mb/s ACK
	mmio32 0x00D40000, MMIO_SHM_DATA	// high: NAV for 11Mb/s ACK (should be 213us = 14*8/11 + 192 + 10 ceiled, instead it is 212??) low: --
	mmio32 0x0033846E, MMIO_SHM_DATA
	mmio32 0x00FCC02C, MMIO_SHM_DATA

.initvals(b0g0bsinitvals5)
	
	mmio16 0x0B4E, 0x686
	mmio16 0x3E3E, 0x680
	mmio16 0x023E, 0x682
	mmio16 0x003C, 0x700
	mmio16 0x0212, 0x684

	// write SHM again
	mmio32 0x10003, MMIO_SHM_CONTROL
	mmio16 0x000C0, MMIO_SHM_DATA		// aPHY-RX-START-Delay
	mmio32 0x10003, MMIO_SHM_CONTROL
	mmio16 0x0000A, MMIO_SHM_DATA_UNALIGNED // EDCF Status Offset (aSIFSTime)

	mmio32 0x10004, MMIO_SHM_CONTROL
	mmio16 0x14, MMIO_SHM_DATA		// aSlotTime

	mmio32 0x10007, MMIO_SHM_CONTROL
	mmio16 0x183, MMIO_SHM_DATA		// Beacon Transmit TSF Offset

	mmio32 0x10025, MMIO_SHM_CONTROL
	mmio16 0x1F4, MMIO_SHM_DATA		// Pre-wakeup for synth. PU = 500

	mmio32 0x10199, MMIO_SHM_CONTROL
	mmio16 0x3C, MMIO_SHM_DATA

	mmio32 0x1019E, MMIO_SHM_CONTROL
	mmio16 0x34, MMIO_SHM_DATA

	mmio32 0x101A3, MMIO_SHM_CONTROL
	mmio16 0x30, MMIO_SHM_DATA

	mmio32 0x101A8, MMIO_SHM_CONTROL
	mmio16 0x2C, MMIO_SHM_DATA

	mmio32 0x101AD, MMIO_SHM_CONTROL
	mmio16 0x2C, MMIO_SHM_DATA

	mmio32 0x101B2, MMIO_SHM_CONTROL
	mmio16 0x28, MMIO_SHM_DATA

	mmio32 0x101B7, MMIO_SHM_CONTROL
	mmio16 0x28, MMIO_SHM_DATA

	mmio32 0x101BC, MMIO_SHM_CONTROL
	mmio16 0x28, MMIO_SHM_DATA

	/* Interframe space init */
	//mmio16 0x0B4E, 0x686
	//mmio16 0, MMIO_PHY0
	
.text

// vim: syntax=b43 ts=8
