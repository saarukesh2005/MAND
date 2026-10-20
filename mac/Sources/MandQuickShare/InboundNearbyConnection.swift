// Adapted for M’AND from NearDrop by Grishka (https://github.com/grishka/NearDrop), Unlicense.
// M’AND changes are marked “M’AND:”.
//
//  InboundNearbyConnection.swift
//  NearDrop
//
//  Created by Grishka on 08.04.2023.
//

import Foundation
import Network
import CryptoKit
import CommonCrypto
import System

import MandCore

class InboundNearbyConnection: NearbyConnection{
	
	private var currentState:State = .initial
	public weak var delegate:InboundNearbyConnectionDelegate?
	private var cipherCommitment:Data?
	
	private var textPayloadID:Int64=0
	/// M’AND: results reported to the app when the connection ends.
	private(set) var savedFiles:[URL]=[]
	private(set) var receivedLink:URL?
	private var totalBytes:Int64=0
	private var savedBytes:Int64=0
	
	enum State{
		case initial, receivedConnectionRequest, sentUkeyServerInit, receivedUkeyClientFinish, sentConnectionResponse, sentPairedKeyResult, receivedPairedKeyResult, waitingForUserConsent, receivingFiles, disconnected
	}
	
	override init(connection: NWConnection, id:String) {
		super.init(connection: connection, id: id)
	}
	
	override func handleConnectionClosure() {
		super.handleConnectionClosure()
		currentState = .disconnected
		try? deletePartiallyReceivedFiles()
		DispatchQueue.main.async {
			self.delegate?.connectionWasTerminated(connection: self, error: self.lastError)
		}
	}
	
	override internal func processReceivedFrame(frameData:Data){
		do{
			switch currentState {
			case .initial:
				let frame=try Location_Nearby_Connections_OfflineFrame(serializedData: frameData)
				try processConnectionRequestFrame(frame)
			case .receivedConnectionRequest:
				let msg=try Securegcm_Ukey2Message(serializedData: frameData)
				ukeyClientInitMsgData=frameData
				try processUkey2ClientInit(msg)
			case .sentUkeyServerInit:
				let msg=try Securegcm_Ukey2Message(serializedData: frameData)
				try processUkey2ClientFinish(msg, raw: frameData)
			case .receivedUkeyClientFinish:
				let frame=try Location_Nearby_Connections_OfflineFrame(serializedData: frameData)
				try processConnectionResponseFrame(frame)
			default:
				let smsg=try Securemessage_SecureMessage(serializedData: frameData)
				try decryptAndProcessReceivedSecureMessage(smsg)
			}
		}catch{
			lastError=error
			protocolError()
		}
	}
	
	override internal func processTransferSetupFrame(_ frame:Sharing_Nearby_Frame) throws{
		if frame.hasV1 && frame.v1.hasType, case .cancel = frame.v1.type {
			try sendDisconnectionAndDisconnect()
			return
		}
		switch currentState{
		case .sentConnectionResponse:
			try processPairedKeyEncryptionFrame(frame)
		case .sentPairedKeyResult:
			try processPairedKeyResultFrame(frame)
		case .receivedPairedKeyResult:
			try processIntroductionFrame(frame)
		default:
			throw NearbyError.protocolError("Unexpected transfer setup frame")
		}
	}
	
	override func isServer() -> Bool {
		return true
	}
	
	override func processFileChunk(frame: Location_Nearby_Connections_PayloadTransferFrame) throws{
		guard currentState == .receivingFiles else { throw NearbyError.protocolError("File data before the user accepted") }
		let id=frame.payloadHeader.id
		guard let fileInfo=transferredFiles[id] else { throw NearbyError.protocolError("File payload ID \(id) is not known") }
		let currentOffset=fileInfo.bytesTransferred
		guard frame.payloadChunk.offset==currentOffset else { throw NearbyError.protocolError("Invalid offset into file \(frame.payloadChunk.offset), expected \(currentOffset)") }
		guard currentOffset+Int64(frame.payloadChunk.body.count)<=fileInfo.meta.size else { throw NearbyError.protocolError("Transferred file size exceeds previously specified value") }
		if frame.payloadChunk.body.count>0{
			try fileInfo.fileHandle?.write(contentsOf: frame.payloadChunk.body)
			transferredFiles[id]!.bytesTransferred+=Int64(frame.payloadChunk.body.count)
			reportProgress()
		}
		if (frame.payloadChunk.flags & 1)==1{
			try finishFile(id)
		}
	}
	
	override func processBytesPayload(payload: Data, id: Int64) throws -> Bool {
		if id==textPayloadID{
			// M’AND: links are never opened automatically; the app shows them with an Open button.
			guard currentState == .receivingFiles else { throw NearbyError.protocolError("Link before the user accepted") }
			if let urlStr=String(data: payload, encoding: .utf8), let url=URL(string: urlStr),
			   let scheme=url.scheme?.lowercased(), scheme=="http" || scheme=="https"{
				receivedLink=url
			}
			try sendDisconnectionAndDisconnect()
			return true
		}else if transferredFiles[id] != nil{
			guard currentState == .receivingFiles else { throw NearbyError.protocolError("File data before the user accepted") }
			guard Int64(payload.count)==transferredFiles[id]!.meta.size else { throw NearbyError.protocolError("Size mismatch") }
			try transferredFiles[id]!.fileHandle?.write(contentsOf: payload)
			transferredFiles[id]!.bytesTransferred+=Int64(payload.count)
			try finishFile(id)
			return true
		}
		return false
	}
	
	/// M’AND: verifies the size, then moves the finished file into the download folder under a
	/// safe, unique name. Incomplete files are never moved.
	private func finishFile(_ id:Int64) throws{
		guard var info=transferredFiles[id] else { return }
		try info.fileHandle?.close()
		info.fileHandle=nil
		transferredFiles[id]=info
		guard info.bytesTransferred==info.meta.size else { throw NearbyError.protocolError("File ended early") }
		let root=QuickShareConfig.current.destination()
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let name=SafeFileName.uniqueName(info.safeName) { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
		guard let target=SafeFileName.contained([name], in: root) else { throw NearbyError.protocolError("Unsafe destination") }
		try FileManager.default.moveItem(at: info.partURL, to: target)
		transferredFiles.removeValue(forKey: id)
		savedFiles.append(target)
		savedBytes+=info.meta.size
		reportProgress()
		if transferredFiles.isEmpty{
			try sendDisconnectionAndDisconnect()
		}
	}
	
	private func reportProgress(){
		let received=transferredFiles.values.reduce(Int64(0)) { $0+$1.bytesTransferred }+savedBytes
		let total=totalBytes
		let done=savedFiles.count
		let connectionID=id
		DispatchQueue.main.async { self.delegate?.transferProgress(id: connectionID, received: received, total: total, filesDone: done) }
	}
	
	private func processConnectionRequestFrame(_ frame:Location_Nearby_Connections_OfflineFrame) throws{
		guard frame.hasV1 && frame.v1.hasConnectionRequest && frame.v1.connectionRequest.hasEndpointInfo else { throw NearbyError.requiredFieldMissing("connectionRequest.endpointInfo") }
		guard case .connectionRequest = frame.v1.type else { throw NearbyError.protocolError("Unexpected frame type \(frame.v1.type)") }
		let endpointInfo=frame.v1.connectionRequest.endpointInfo
		guard endpointInfo.count>17 else { throw NearbyError.protocolError("Endpoint info too short") }
		let deviceNameLength=Int(endpointInfo[17])
		guard endpointInfo.count>=deviceNameLength+18 else { throw NearbyError.protocolError("Endpoint info too short to contain the device name") }
		guard let deviceName=String(data: endpointInfo[18..<(18+deviceNameLength)], encoding: .utf8) else { throw NearbyError.protocolError("Device name is not valid UTF-8") }
		let rawDeviceType:Int=Int(endpointInfo[0] & 7) >> 1
		remoteDeviceInfo=RemoteDeviceInfo(name: deviceName, type: RemoteDeviceInfo.DeviceType.fromRawValue(value: rawDeviceType))
		currentState = .receivedConnectionRequest
	}
	
	private func processUkey2ClientInit(_ msg:Securegcm_Ukey2Message) throws{
		guard msg.hasMessageType, msg.hasMessageData else { throw NearbyError.requiredFieldMissing("clientInit ukey2message.type|data") }
		guard case .clientInit = msg.messageType else{
			sendUkey2Alert(type: .badMessageType)
			throw NearbyError.ukey2
		}
		let clientInit:Securegcm_Ukey2ClientInit
		do{
			clientInit=try Securegcm_Ukey2ClientInit(serializedData: msg.messageData)
		}catch{
			sendUkey2Alert(type: .badMessageData)
			throw NearbyError.ukey2
		}
		guard clientInit.version==1 else{
			sendUkey2Alert(type: .badVersion)
			throw NearbyError.ukey2
		}
		guard clientInit.random.count==32 else{
			sendUkey2Alert(type: .badRandom)
			throw NearbyError.ukey2
		}
		var found=false
		for commitment in clientInit.cipherCommitments{
			if case .p256Sha512 = commitment.handshakeCipher{
				found=true
				cipherCommitment=commitment.commitment
				break
			}
		}
		guard found else{
			sendUkey2Alert(type: .badHandshakeCipher)
			throw NearbyError.ukey2
		}
		guard clientInit.nextProtocol=="AES_256_CBC-HMAC_SHA256" else{
			sendUkey2Alert(type: .badNextProtocol)
			throw NearbyError.ukey2
		}
		
		let privKey=P256.KeyAgreement.PrivateKey()
		privateKey=privKey
		let x963=privKey.publicKey.x963Representation // 0x04 || X(32) || Y(32)
		
		var serverInit=Securegcm_Ukey2ServerInit()
		serverInit.version=1
		serverInit.random=Data.randomData(length: 32)
		serverInit.handshakeCipher = .p256Sha512
		
		var pkey=Securemessage_GenericPublicKey()
		pkey.type = .ecP256
		pkey.ecP256PublicKey=Securemessage_EcP256PublicKey()
		pkey.ecP256PublicKey.x=NearbyConnection.signedBytes(x963.subdata(in: 1..<33))
		pkey.ecP256PublicKey.y=NearbyConnection.signedBytes(x963.subdata(in: 33..<65))
		serverInit.publicKey=try pkey.serializedData()
		
		var serverInitMsg=Securegcm_Ukey2Message()
		serverInitMsg.messageType = .serverInit
		serverInitMsg.messageData=try serverInit.serializedData()
		let serverInitData=try serverInitMsg.serializedData()
		ukeyServerInitMsgData=serverInitData
		sendFrameAsync(serverInitData)
		currentState = .sentUkeyServerInit
	}
	
	private func processUkey2ClientFinish(_ msg:Securegcm_Ukey2Message, raw:Data) throws{
		guard msg.hasMessageType, msg.hasMessageData else { throw NearbyError.requiredFieldMissing("clientFinish ukey2message.type|data") }
		guard case .clientFinish = msg.messageType else { throw NearbyError.ukey2 }
		
		var sha=SHA512()
		sha.update(data: raw)
		guard cipherCommitment==Data(sha.finalize()) else { throw NearbyError.ukey2 }
		
		let clientFinish=try Securegcm_Ukey2ClientFinished(serializedData: msg.messageData)
		guard clientFinish.hasPublicKey else {throw NearbyError.requiredFieldMissing("ukey2clientFinish.publicKey") }
		let clientKey=try Securemessage_GenericPublicKey(serializedData: clientFinish.publicKey)
		
		try finalizeKeyExchange(peerKey: clientKey)
		
		currentState = .receivedUkeyClientFinish
	}
	
	private func processConnectionResponseFrame(_ frame:Location_Nearby_Connections_OfflineFrame) throws{
		guard frame.hasV1, frame.v1.hasType else { throw NearbyError.requiredFieldMissing("offlineFrame.v1.type") }
		if case .connectionResponse = frame.v1.type {
			var resp=Location_Nearby_Connections_OfflineFrame()
			resp.version = .v1
			resp.v1=Location_Nearby_Connections_V1Frame()
			resp.v1.type = .connectionResponse
			resp.v1.connectionResponse=Location_Nearby_Connections_ConnectionResponseFrame()
			resp.v1.connectionResponse.response = .accept
			resp.v1.connectionResponse.status=0
			resp.v1.connectionResponse.osInfo=Location_Nearby_Connections_OsInfo()
			resp.v1.connectionResponse.osInfo.type = .apple
			sendFrameAsync(try resp.serializedData())
			
			encryptionDone=true
			
			var pairedEncryption=Sharing_Nearby_Frame()
			pairedEncryption.version = .v1
			pairedEncryption.v1=Sharing_Nearby_V1Frame()
			pairedEncryption.v1.type = .pairedKeyEncryption
			pairedEncryption.v1.pairedKeyEncryption=Sharing_Nearby_PairedKeyEncryptionFrame()
			// Presumably used for all the phone number stuff that no one needs anyway
			pairedEncryption.v1.pairedKeyEncryption.secretIDHash=Data.randomData(length: 6)
			pairedEncryption.v1.pairedKeyEncryption.signedData=Data.randomData(length: 72)
			try sendTransferSetupFrame(pairedEncryption)
			currentState = .sentConnectionResponse
		}
	}
	
	private func processPairedKeyEncryptionFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyEncryption else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.pairedKeyEncryption") }
		var pairedResult=Sharing_Nearby_Frame()
		pairedResult.version = .v1
		pairedResult.v1=Sharing_Nearby_V1Frame()
		pairedResult.v1.type = .pairedKeyResult
		pairedResult.v1.pairedKeyResult=Sharing_Nearby_PairedKeyResultFrame()
		pairedResult.v1.pairedKeyResult.status = .unable
		try sendTransferSetupFrame(pairedResult)
		currentState = .sentPairedKeyResult
	}
	
	private func processPairedKeyResultFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasPairedKeyResult else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.pairedKeyResult") }
		currentState = .receivedPairedKeyResult
	}
	
	private func processIntroductionFrame(_ frame:Sharing_Nearby_Frame) throws{
		guard frame.hasV1, frame.v1.hasIntroduction else { throw NearbyError.requiredFieldMissing("shareNearbyFrame.v1.introduction") }
		currentState = .waitingForUserConsent
		let config=QuickShareConfig.current
		let partFolder=config.partialFolder
		try FileManager.default.createDirectory(at: partFolder, withIntermediateDirectories: true)
		let intro=frame.v1.introduction
		if intro.fileMetadata.count>0 && intro.textMetadata.isEmpty{
			// M’AND: limits on count and size; names cleaned by the same rules as M’AND transfers.
			guard intro.fileMetadata.count<=QuickShareConfig.maxFiles else { return rejectTransfer(with: .unsupportedAttachmentType) }
			var total:Int64=0
			for file in intro.fileMetadata{
				guard file.size>=0, file.size<=QuickShareConfig.maxFileSize else { return rejectTransfer(with: .notEnoughSpace) }
				total+=file.size
				let safe=(try? SafeFileName.components(of: file.name))?.last ?? "Quick Share file"
				transferredFiles[file.payloadID]=InternalFileInfo(
					meta: FileMetadata(name: safe, size: file.size, mimeType: file.mimeType),
					payloadID: file.payloadID, safeName: safe,
					partURL: partFolder.appendingPathComponent("qs-\(UUID().uuidString).part"))
			}
			guard total<=config.availableSpace() else { return rejectTransfer(with: .notEnoughSpace) }
			totalBytes=total
			let metadata=TransferMetadata(files: transferredFiles.map({$0.value.meta}), id: id, pinCode: pinCode)
			DispatchQueue.main.async {
				self.delegate?.obtainUserConsent(for: metadata, from: self.remoteDeviceInfo!, connection: self)
			}
		}else if intro.textMetadata.count==1{
			let meta=intro.textMetadata[0]
			if case .url=meta.type{
				let metadata=TransferMetadata(files: [], id: id, pinCode: pinCode, textDescription: meta.textTitle)
				textPayloadID=meta.payloadID
				DispatchQueue.main.async {
					self.delegate?.obtainUserConsent(for: metadata, from: self.remoteDeviceInfo!, connection: self)
				}
			}else if case .text=meta.type{
				guard meta.size>=0, meta.size<=QuickShareConfig.maxTextSize else { return rejectTransfer(with: .unsupportedAttachmentType) }
				let dateFormatter=DateFormatter()
				dateFormatter.dateFormat="yyyy-MM-dd HH.mm.ss"
				let name="Quick Share text \(dateFormatter.string(from: Date())).txt"
				let info=InternalFileInfo(meta: FileMetadata(name: name, size: meta.size, mimeType: "text/plain"),
										  payloadID: meta.payloadID, safeName: name,
										  partURL: partFolder.appendingPathComponent("qs-\(UUID().uuidString).part"))
				transferredFiles[meta.payloadID]=info
				totalBytes=meta.size
				DispatchQueue.main.async {
					self.delegate?.obtainUserConsent(for: TransferMetadata(files: [info.meta], id: self.id, pinCode: self.pinCode), from: self.remoteDeviceInfo!, connection: self)
				}
			}else{
				rejectTransfer(with: .unsupportedAttachmentType)
			}
		}else{
			rejectTransfer(with: .unsupportedAttachmentType)
		}
	}
	
	func submitUserConsent(accepted:Bool){
		NearbyConnection.queue.async {
			guard self.currentState == .waitingForUserConsent else { return }
			if accepted{
				self.acceptTransfer()
			}else{
				self.rejectTransfer()
			}
		}
	}
	
	private func acceptTransfer(){
		do{
			for (id, file) in transferredFiles{
				FileManager.default.createFile(atPath: file.partURL.path, contents: nil)
				transferredFiles[id]!.created=true
				transferredFiles[id]!.fileHandle=try FileHandle(forWritingTo: file.partURL)
			}
			var frame=Sharing_Nearby_Frame()
			frame.version = .v1
			frame.v1.type = .response
			frame.v1.connectionResponse.status = .accept
			currentState = .receivingFiles
			try sendTransferSetupFrame(frame)
		}catch{
			lastError=error
			protocolError()
		}
	}
	
	private func rejectTransfer(with reason:Sharing_Nearby_ConnectionResponseFrame.Status = .reject){
		var frame=Sharing_Nearby_Frame()
		frame.version = .v1
		frame.v1.type = .response
		frame.v1.connectionResponse.status = reason
		do{
			try sendTransferSetupFrame(frame)
			try sendDisconnectionAndDisconnect()
		}catch{
			protocolError()
		}
	}
	
	/// M’AND: removes only the hidden partial files; finished files were already moved out.
	private func deletePartiallyReceivedFiles() throws{
		for (_, file) in transferredFiles{
			try? file.fileHandle?.close()
			guard file.created else { continue }
			try? FileManager.default.removeItem(at: file.partURL)
		}
	}
}

protocol InboundNearbyConnectionDelegate: AnyObject{
	func obtainUserConsent(for transfer:TransferMetadata, from device:RemoteDeviceInfo, connection:InboundNearbyConnection)
	func transferProgress(id:String, received:Int64, total:Int64, filesDone:Int)
	func connectionWasTerminated(connection:InboundNearbyConnection, error:Error?)
}
