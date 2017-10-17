-------------------------------------------------------------------------------
--        
--		Copyright (C) 2014 - 2017 Jeff Stenhouse, René Richard
-- 
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
-------------------------------------------------------------------------------
--
--    Target Hardware:
--    https://github.com/db-electronics/pc-henshin-protel

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PCHenshin is

	port(
		data_bus		:	inout std_logic_vector(7 downto 0);
		--nRST			:	in std_logic;
		nOEin			:	in std_logic;
		nCE			:	in std_logic;

		nOEout		:  out std_logic;

		-- These are just for simulation and debug.
		OEdata_p		:	out std_logic
		--debug_p		:	out std_logic_vector(3 downto 0)
	);
	
end PCHenshin;

architecture PCHenshin_a of PCHenshin is

    -- define the states of FSM model
	 -- the following in unorthodox but will help with array indexing
    type state_type is (S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11);
    --signal current_state: integer range 0 to 15;
	 signal current_state: state_type;

	 -- define the ROM sequence we are looking for
	 type ROM8 is array (0 to 6) of std_logic_vector(7 downto 0);
	 constant RegionSequence		: ROM8 :=
			(x"78", x"54", x"A9", x"FF", x"53", x"01", x"AD");
	 constant ReversedRegionSequence		: ROM8 :=
			(x"1E", x"2A", x"95", x"FF", x"CA", x"80", x"B5");

	 --constant PatchByte : std_logic_vector(7 downto 0) := x"80";
	 --constant ReversedPatchByte : std_logic_vector(7 downto 0) := x"01";

	 -- internal databus signals make it easier to drive an inout external port
	 signal datain_s		:	std_logic_vector(7 downto 0);
	 --signal dataout_s		:	std_logic_vector(7 downto 0);

	 -- tells us if the data lines are flipped (i.e. it's a PCE game with a region lock)
	 signal flip_bit		: std_logic;
	 
	 -- this signal will enable driving data out to the databus
	 signal OE_data_s		:  std_logic;

	 -- This holds the OR of /OE and /CE.  This way, if /CE is high, we ignore /OE.
	 signal byteClock		:  std_logic;
	 
begin

	-- drive databus only when needed, else tri-state it.  We're writing out a byte of 0 when we override the data (when OE_data_s is '1').
	data_bus <= (others=>'0') when (OE_data_s = '1' and byteClock = '0')
					else (others=>'Z');
	
	-- drive nOEout to the HuCard when we don't need to drive the databus
	nOEout <= nOEin when OE_data_s = '0' else '1';
	
	-- byteClock only goes low when the signal has gone through some inverters and still is happy, for debounce purposes.
	byteClock <= nOEin or nCE;

	-- OE_data_s tells us when to override /OE and output data.
	OE_data_s <= '1' when (current_state = S9) else '0';
	OEdata_p <= OE_data_s;

	-- Bring the current state out to the debug header.
	--debug_p <= std_logic_vector(to_unsigned(current_state, debug_p'length));
	--debug_p(0) <= '1' when (current_state = S9) else '0';
	--debug_p(1) <= '1' when (current_state = S1) else '0';
	--debug_p(2) <= '1' when (current_state = S2) else '0';
	--debug_p(3) <= '1' when (current_state = S5) else '0';

	--datain_s <= data_bus when (nOEin = '0') else datain_s;

--	process(nOEin)
--	begin
--		-- We're sampling the data bus when /OE rises, so that when we evaluate state
--		-- (when /OE OR /CE rises, slightly later), it should have a good sample of data.
--		if (rising_edge(nOEin)) then
--			datain_s <= data_bus;
--		end if;
--	end process;

	comb_logic: process(nOEin)
	begin
		if (rising_edge(nOEin)) then -- When /OE or /CE rises, switch to the next state (maybe).
			if (nCE = '0') then
				case current_state is
				when S0 => -- look for 0x54
					if data_bus = ReversedRegionSequence(1) then
						flip_bit <= '1';
						current_state <= S1;
					elsif data_bus = RegionSequence(1) then
						flip_bit <= '0';
						current_state <= S1;
					end if;

				when S1 => -- Check for the next byte (0xA9)
					case flip_bit is
					when '1' =>
						-- If we see the next byte, move to the next byte.
						if ReversedRegionSequence(2) = data_bus then
							current_state <= S2;
						-- If we see the first byte of the sequence, go back to state #1
						-- in case we were in the middle of the state machine and then it restarted unexpectedly.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					when others =>
						-- If we see the next byte, move to the next byte.
						if data_bus = RegionSequence(2) then
							current_state <= S2;
						-- If we see the first byte of the sequence, go back to state #1
						-- in case we were in the middle of the state machine and then it restarted unexpectedly.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					end case;

				when S2 => -- Check for the next byte (0xFF)
					case flip_bit is
					when '1' =>
						-- If we see the next byte, move to the next byte.
						if ReversedRegionSequence(3) = data_bus then
							current_state <= S3;
						-- Allow for the byte 0xA9 to be repeated on the bus.
						elsif ReversedRegionSequence(2) = data_bus then
							current_state <= S2;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					when others =>
						-- If we see the next byte, move to the next byte.
						if data_bus = RegionSequence(3) then
							current_state <= S3;
						-- Allow for the byte to be repeated on the bus.
						elsif data_bus = RegionSequence(2) then
							current_state <= S2;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					end case;

				when S3 => -- Check for the next byte (0x53)
					case flip_bit is
					when '1' =>
						-- If we see the next byte, move to the next byte.
						if ReversedRegionSequence(4) = data_bus then
							current_state <= S4;
						-- Allow for the byte 0xFF to be repeated on the bus.
						elsif ReversedRegionSequence(3) = data_bus then
							current_state <= S3;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					when others =>
						-- If we see the next byte, move to the next byte.
						if data_bus = RegionSequence(4) then
							current_state <= S4;
						-- Allow for the byte to be repeated on the bus.
						elsif data_bus = RegionSequence(3) then
							current_state <= S3;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					end case;

				when S4 => -- Check for the next byte (0x01)
					case flip_bit is
					when '1' =>
						-- If we see the next byte, move to the next byte.
						if ReversedRegionSequence(5) = data_bus then
							current_state <= S5;
						-- Allow for the byte 0x53 to be repeated on the bus.
						elsif ReversedRegionSequence(4) = data_bus then
							current_state <= S4;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					when others =>
						-- If we see the next byte, move to the next byte.
						if data_bus = RegionSequence(5) then
							current_state <= S5;
						-- Allow for the byte to be repeated on the bus.
						elsif data_bus = RegionSequence(4) then
							current_state <= S4;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					end case;

				when S5 => -- Check for the next byte (0xAD)
					case flip_bit is
					when '1' =>
						-- If we see the next byte, move to the next byte.
						if ReversedRegionSequence(6) = data_bus then
							current_state <= S6;
						-- Allow for the byte 0x01 to be repeated on the bus.
						elsif ReversedRegionSequence(5) = data_bus then
							current_state <= S5;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					when others =>
						-- If we see the next byte, move to the next byte.
						if data_bus = RegionSequence(6) then
							current_state <= S6;
						-- Allow for the byte to be repeated on the bus.
						elsif data_bus = RegionSequence(5) then
							current_state <= S5;
						-- Allow for the sequence to be restarted when we see the first byte again.
						elsif data_bus = ReversedRegionSequence(1) then
							flip_bit <= '1';
							current_state <= S1;
						elsif data_bus = RegionSequence(1) then
							flip_bit <= '0';
							current_state <= S1;
						-- If we don't recognize the byte, start over completely.
						else
							current_state <= S0;
						end if;
					end case;

				when S6 => -- We've checked the bytes... start counting off.
					-- This byte will be 0x00 going across the bus.
					current_state <= S7;

				when S7 =>
					-- This byte will be 0x10 going across the bus.
					current_state <= S8;

				when S8 =>
					-- This byte will be 0x29 going across the bus -- SMASH NEXT BYTE!
					current_state <= S9;

				when others =>
					-- We're starting over.
					current_state <= S0;
				end case;
			end if;
		end if;
	end process;

end PCHenshin_a;
