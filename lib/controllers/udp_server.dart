import 'dart:io';
import 'dart:async';
import 'package:validator/validator.dart';
import 'package:flutter/material.dart';
import 'package:d_artnet/d_artnet.dart';

import 'package:flutter/material.dart';
import 'package:d_artnet/d_artnet.dart';

import 'package:redux/redux.dart';
import 'package:flutter_redux/flutter_redux.dart';

import 'package:artnet_tester/models/action.dart';
import 'package:artnet_tester/models/app_state.dart';
import 'package:artnet_tester/models/network_settings.dart';
import 'package:artnet_tester/models/packet.dart';

import 'package:artnet_tester/views/main_screen.dart';
import 'package:artnet_tester/views/network_settings_screen.dart';

import 'package:artnet_tester/controllers/reducers.dart';
import 'package:artnet_tester/controllers/udp_server.dart';

final UdpServerController server = new UdpServerController();

class UdpServerController{
  static const String broadcast = "255.255.255.255";
  static const int artnetPort = 6454;

  bool _connected = false;

  RawDatagramSocket _socket;
  Store _store;
  InternetAddress _ownIp = InternetAddress.anyIPv4;
  String _outgoingIp = broadcast;
  int _outgoingPort = artnetPort;
  int _uuid = 0;

  UdpServerController([String ip, int port, Store store]){
    if(ip != null) this.outgoingIp = ip;
    if(port != null) this.outgoingPort = port;
    if(store != null) this._store = store;
    RawDatagramSocket.bind(InternetAddress.anyIPv4, artnetPort).then((RawDatagramSocket socket){
      this._socket = socket;
      this._uuid = generateUUID32(3);
      print('UDP ready to receive');
      print('${socket.address.address}:${socket.port} - ${this._uuid}');
      this._connected = true;
      this._socket.broadcastEnabled = true;
      this._socket.listen(_handlePacket);

      //Kick off Timers!
      sendPacket(ArtnetBeepBeepPacket(this._uuid).udpPacket, broadcast, artnetPort);
      new Timer(Duration(seconds: 3), _tick);
      new Timer(Duration(seconds: 9), _beep);
    });
  }

  void setStore(Store store){
    this._store = store;
  }

  String get outgoingIp => this._outgoingIp;
  set outgoingIp(String value) => this._outgoingIp = (isIP(value)) ? value : broadcast;

  int get outgoingPort => this._outgoingPort;
  set outgoingPort(int value) => this._outgoingPort = (value < 0) ? artnetPort : value;

  void _handlePacket(RawSocketEvent e){
    Datagram gram = _socket.receive();
    var packet;
    if (gram == null) return;

    if(!checkArtnetPacket(gram.data)) return;

    if(getOpCode(gram.data) ==  ArtnetBeepBeepPacket.opCode){
      packet = ArtnetBeepBeepPacket(null, gram.data);
      if(packet.uuid == this._uuid){
        this._ownIp = gram.address;
        print("Own ip: " + this._ownIp.toString());
      }
    }

    if(this._ownIp == gram.address) return;

    switch(getOpCode(gram.data)){
      case ArtnetDataPacket.opCode:
        packet = Packet(true, ArtnetDataPacket(gram.data));
      break;
      case ArtnetPollPacket.opCode:
        packet = Packet(true, ArtnetPollPacket(gram.data));
        sendPacket(_populateOutgoingPollReply(), gram.address);
      break;
      case ArtnetPollReplyPacket.opCode:
        packet = Packet(true, ArtnetPollReplyPacket(gram.data));
        //sendPacket(gram.data, gram.address);
      break;
      case ArtnetAddressPacket.opCode:
        packet = Packet(true, ArtnetAddressPacket(gram.data));
      break;
      case ArtnetIpProgPacket.opCode:
        packet = Packet(true, ArtnetIpProgPacket(gram.data));
      break;
      case ArtnetIpProgReplyPacket.opCode:
        packet = Packet(true, ArtnetIpProgReplyPacket(gram.data));
      break;
      case ArtnetCommandPacket.opCode:
        packet = Packet(true, ArtnetCommandPacket(gram.data));
      break;
      case ArtnetSyncPacket.opCode:
        packet = Packet(true, ArtnetSyncPacket(gram.data));
      break;
      case ArtnetFirmwareMasterPacket.opCode:
        packet = Packet(true, ArtnetFirmwareMasterPacket(gram.data));
      break;
      case ArtnetFirmwareReplyPacket.opCode:
        packet = Packet(true, ArtnetFirmwareReplyPacket(gram.data));
      break;
      default:
        return; //unknown packet
    }


    if(this._store != null){
      this._store.dispatch(new ArtnetAction(Actions.addPacket, packet));
    } else {
      print("Error: Null store");
      return;
    }

  }

  void sendPacket(List<int> packet,[ip, int port]){
    InternetAddress ipToSend = InternetAddress(broadcast);
    int portToSend = (port == null) ? this._outgoingPort : port; 

    if(ip != null){
      if(ip is String){
        if(isIP(ip)){
          ipToSend = InternetAddress(ip);
        } else return;
      } else if(ip is InternetAddress){
        ipToSend = (ip as InternetAddress);
      } else return;
    }
    

    if(_connected) _socket.send(packet, ipToSend, portToSend);
  
  }

  void _tick(){
    ArtnetPollPacket packet = ArtnetPollPacket();

    sendPacket(packet.udpPacket, broadcast, artnetPort);
    //print("tick");
    new Timer(Duration(seconds: 33), _tick);
  }

  void _beep(){
    ArtnetBeepBeepPacket packet = ArtnetBeepBeepPacket(this._uuid);

    sendPacket(packet.udpPacket, broadcast, artnetPort);
    //print("beep");
    new Timer(Duration(seconds: 333), _beep);
  }

  List<int> _populateOutgoingPollReply(){
    ArtnetPollReplyPacket reply = ArtnetPollReplyPacket();

    reply.ip = this._ownIp.rawAddress;

    reply.port = 0x1936;

    reply.versionInfoH = 0;
    reply.versionInfoL = 1;

    reply.universe = 0;

    reply.oemHi = 0x12;
    reply.oemLo = 0x51;

    reply.ubeaVersion = 0;

    reply.status1ProgrammingAuthority = 2;
    reply.status1IndicatorState = 2;

    reply.estaManHi = 0x01;
    reply.estaManLo = 0x04;

    reply.shortName = "Baa";
    reply.longName = "Blizzard Art-Net Analyzer - Baa";

    reply.nodeReport = "!Enjoy the little things!";
    //reply.packet.setUint8(ArtnetPollReplyPacket.nodeReportIndex, 0); //Sometimes you have to look for the little things

    reply.numPorts = 1;

    reply.portTypes[0] = ArtnetPollReplyPacket.portTypesProtocolOptionDMX;

    reply.style = ArtnetPollReplyPacket.styleOptionStNode;

    reply.status2HasWebConfigurationSupport = true;
    reply.status2DHCPCapable = true;

    return reply.udpPacket;
  }
}

