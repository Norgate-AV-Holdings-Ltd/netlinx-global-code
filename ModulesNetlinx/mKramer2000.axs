MODULE_NAME='mKramer2000'(DEV vdvControl, DEV dvDevice)
INCLUDE 'CustomFunctions'
/******************************************************************************
	Strutcures Etc
******************************************************************************/
DEFINE_CONSTANT
LONG TLID_SEND  = 1
LONG TLID_POLL  = 2
LONG TLID_COMMS = 3
LONG TLID_RETRY = 4

INTEGER CONN_STATE_OFFLINE		= 0
INTEGER CONN_STATE_CONNECTING	= 1
INTEGER CONN_STATE_CONNECTED		= 2

DEFINE_TYPE STRUCTURE uKramer2k{
	INTEGER 	DEBUG
	CHAR 		Tx[100][4]
	CHAR 		IP_HOST[255]
	INTEGER 	CONN_STATE
	INTEGER  isIP
}

DEFINE_VARIABLE
VOLATILE uKramer2k myKramer2k
VOLATILE LONG TLT_SEND[]  = {   100 }
VOLATILE LONG TLT_POLL[]  = { 15000 }
VOLATILE LONG TLT_COMMS[] = { 35000 }
VOLATILE LONG TLT_RETRY[] = {  5000 }

/******************************************************************************
	Module Startup
******************************************************************************/
DEFINE_START{
	myKramer2k.isIP = !(dvDEVICE.NUMBER)
}
/******************************************************************************
	IP Functions
******************************************************************************/
DEFINE_FUNCTION fnOpenTCPConnection(){
	IF(myKramer2k.IP_HOST == ''){
		fnDebug('Kramer IP','Not Set')
	}
	ELSE{
		fnDebug('Connecting to Kramer on ',"myKramer2k.IP_HOST,':5000'")
		myKramer2k.CONN_STATE = CONN_STATE_CONNECTING
		ip_client_open(dvDevice.port, myKramer2k.IP_HOST, 5000, IP_TCP)
	}
}
DEFINE_FUNCTION fnCloseTCPConnection(){
	IP_CLIENT_CLOSE(dvDevice.port)
}
DEFINE_FUNCTION fnRetryConnection(){
	IF(TIMELINE_ACTIVE(TLID_RETRY)){TIMELINE_KILL(TLID_RETRY)}
	TIMELINE_CREATE(TLID_RETRY,TLT_RETRY,LENGTH_ARRAY(TLT_RETRY),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
}
DEFINE_EVENT TIMELINE_EVENT[TLID_RETRY]{
	fnOpenTCPConnection()
}

DEFINE_FUNCTION fnSendCommand(char cmd[]){
	IF(!TIMELINE_ACTIVE(TLID_SEND)){
		SEND_STRING dvDevice,"cmd"
		TIMELINE_CREATE(TLID_SEND,TLT_SEND,LENGTH_ARRAY(TLT_SEND),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
	}
	ELSE{
		STACK_VAR INTEGER x
		FOR(x = 1; x <= 100; x++){
			IF(myKramer2K.Tx[x] == ''){
				myKramer2K.Tx[x] = cmd
				BREAK
			}
		}
	}
	fnInitPoll()
}
DEFINE_EVENT TIMELINE_EVENT[TLID_SEND]{
	IF(myKramer2K.Tx[1] != ''){
		STACK_VAR INTEGER x
		SEND_STRING dvDevice, myKramer2K.Tx[1]
		FOR(x = 1; x <= 99; x++){
			myKramer2K.Tx[x] = myKramer2K.Tx[x+1]
			myKramer2K.Tx[x+1] = ''
		}
		TIMELINE_CREATE(TLID_SEND,TLT_SEND,LENGTH_ARRAY(TLT_SEND),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
	}
}

DEFINE_FUNCTION fnInitPoll(){
	IF(TIMELINE_ACTIVE(TLID_POLL)){TIMELINE_KILL(TLID_POLL)}
	TIMELINE_CREATE(TLID_POLL,TLT_POLL,LENGTH_ARRAY(TLT_POLL),TIMELINE_ABSOLUTE,TIMELINE_REPEAT)
}

DEFINE_EVENT TIMELINE_EVENT[TLID_POLL]{
	fnPoll()
}

DEFINE_FUNCTION fnPoll(){
	fnSendCommand( "$05,$80+1,$80+1,$81" )		// Video Status Request for 1x1
}
/******************************************************************************
	Device Control
******************************************************************************/
DEFINE_EVENT DATA_EVENT[dvDevice]{
	ONLINE:{
		myKramer2k.CONN_STATE	= CONN_STATE_CONNECTED
		SEND_COMMAND dvDevice, 'SET MODE DATA'
		SEND_COMMAND dvDevice, 'SET BAUD 9600 N 8 1 485 DISABLE'
		fnPoll()
		fnInitPoll()
	}
	STRING:{
		IF("$48,$80,$80,$81" == DATA.TEXT){
			ON[vdvControl,1]
		}
		ELSE IF("$48,$80,$81,$81" == DATA.TEXT){
			OFF[vdvControl,1]
		}
		ELSE IF($41 == DATA.TEXT[1]) {
			SEND_STRING vdvControl, "'VMATRIX-',ITOA(DATA.TEXT[2]-$80),'*',ITOA(DATA.TEXT[3]-$80)"
		}
		ELSE IF($42 == DATA.TEXT[1]){
			SEND_STRING vdvControl, "'AMATRIX-',ITOA(DATA.TEXT[2]-$80),'*',ITOA(DATA.TEXT[3]-$80)"
		}

		IF(TIMELINE_ACTIVE(TLID_COMMS)){TIMELINE_KILL(TLID_COMMS)}
		TIMELINE_CREATE(TLID_COMMS,TLT_COMMS,LENGTH_ARRAY(TLT_COMMS),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
	}
	OFFLINE:{
		IF(myKramer2k.isIP){
			myKramer2k.CONN_STATE	= CONN_STATE_OFFLINE
			fnRetryConnection()
		}
	}
	ONERROR:{
		IF(myKramer2k.isIP){
			STACK_VAR CHAR _MSG[255]
			SWITCH(DATA.NUMBER){
				CASE 14:_MSG = 'Local Port Already Used'	// Local Port Already Used
				DEFAULT:{
					myKramer2k.CONN_STATE = CONN_STATE_OFFLINE
					SWITCH(DATA.NUMBER){
						CASE 2:{ _MSG = 'General Failure'}					// General Failure - Out Of Memory
						CASE 4:{ _MSG = 'Unknown Host'}						// Unknown Host
						CASE 6:{ _MSG = 'Conn Refused'}						// Connection Refused
						CASE 7:{ _MSG = 'Conn Timed Out'}					// Connection Timed Out
						CASE 8:{ _MSG = 'Unknown'}								// Unknown Connection Error
						CASE 9:{ _MSG = 'Already Closed'}					// Already Closed
						CASE 10:{_MSG = 'Binding Error'} 					// Binding Error
						CASE 11:{_MSG = 'Listening Error'} 					// Listening Error
						CASE 15:{_MSG = 'UDP Socket Already Listening'} // UDP socket already listening
						CASE 16:{_MSG = 'Too many open Sockets'}			// Too many open sockets
						CASE 17:{_MSG = 'Local port not Open'}				// Local Port Not Open
					}
					fnRetryConnection()
				}
			}
			fnDebug("'Kramer IP Error:[',myKramer2k.IP_HOST,']'","'[',ITOA(DATA.NUMBER),'][',_MSG,']'")
		}
	}
}
/******************************************************************************
	Virtual Device
******************************************************************************/

DEFINE_EVENT DATA_EVENT[vdvControl]{
	COMMAND:{
		SWITCH(fnStripCharsRight(REMOVE_STRING(DATA.TEXT,'-',1),1)){
			CASE 'PROPERTY':{
				SWITCH(fnStripCharsRight(REMOVE_STRING(DATA.TEXT,',',1),1)){
					CASE 'IP':{
						myKramer2K.IP_HOST = DATA.TEXT
						fnOpenTCPConnection()
					}
				}
			}
			CASE 'INPUT':{
				STACK_VAR INTEGER _in
				_in = ATOI(DATA.TEXT)
				fnVideoMatrixSwitch(_in,1)
			}
			CASE 'MATRIX':
			CASE 'VMATRIX':{
				STACK_VAR INTEGER _in,_out;
				_in = ATOI(REMOVE_STRING(DATA.TEXT,'*',1))
				_out = ATOI(DATA.TEXT)
				fnVideoMatrixSwitch(_in,_out)
			}
			CASE 'AMATRIX':{
				STACK_VAR INTEGER _in,_out;
				_in = ATOI(REMOVE_STRING(DATA.TEXT,'*',1))
				_out = ATOI(DATA.TEXT)
				fnAudioMatrixSwitch(_in,_out)
			}
			CASE 'AUDIO':{
				IF(DATA.TEXT = 'FOLLOW')fnSendCommand("$08,$80,$80,$81")
				IF(DATA.TEXT = 'BREAK')	fnSendCommand("$08,$80,$81,$81")
			}
		}
	}
}

DEFINE_PROGRAM{
	[vdvControl,251] = (TIMELINE_ACTIVE(TLID_COMMS))
	[vdvControl,252] = (TIMELINE_ACTIVE(TLID_COMMS))
}
/******************************************************************************
	Device Helpers
******************************************************************************/
DEFINE_FUNCTION fnVideoMatrixSwitch(INTEGER _in, INTEGER _out){
	fnSendCommand( "$01,$80+_in,$80+_out,$81" )		// Video Switch
}
DEFINE_FUNCTION fnAudioMatrixSwitch(INTEGER _in, INTEGER _out){
	fnSendCommand( "$02,$80+_in,$80+_out,$81" )		// Audio Switch
}
DEFINE_FUNCTION fnDebug(CHAR Msg[], CHAR MsgData[]){
	IF(myKramer2K.DEBUG = 1){
		SEND_STRING 0:0:0, "ITOA(vdvControl.Number),':',Msg, ':', MsgData"
	}
}
/******************************************************************************
	EoF
******************************************************************************/