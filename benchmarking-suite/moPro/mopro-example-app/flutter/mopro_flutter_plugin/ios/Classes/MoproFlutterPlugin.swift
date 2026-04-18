import Flutter
import Foundation
import UIKit

// MARK: - Flutter-side wrapper types for Groth16 proofs
//
// The Rust side returns Groth16ProofResult which contains Groth16Proof (with G1/G2).
// We mirror that into Flutter-friendly objects and then into the StandardMethodCodec-
// compatible map layout Dart expects.

class FlutterG1 {
  let x: String
  let y: String
  let z: String
  init(x: String, y: String, z: String) { self.x = x; self.y = y; self.z = z }
}

class FlutterG2 {
  let x: [String]
  let y: [String]
  let z: [String]
  init(x: [String], y: [String], z: [String]) { self.x = x; self.y = y; self.z = z }
}

class FlutterGroth16Proof {
  let a: FlutterG1
  let b: FlutterG2
  let c: FlutterG1
  let `protocol`: String
  let curve: String
  init(a: FlutterG1, b: FlutterG2, c: FlutterG1, `protocol`: String, curve: String) {
    self.a = a; self.b = b; self.c = c; self.`protocol` = `protocol`; self.curve = curve
  }
}

class FlutterGroth16ProofResult {
  let proof: FlutterGroth16Proof
  let inputs: [String]
  init(proof: FlutterGroth16Proof, inputs: [String]) {
    self.proof = proof; self.inputs = inputs
  }
}

// MARK: - Groth16 conversions

func convertGroth16Proof(res: Groth16ProofResult) -> [String: Any] {
  let g1a = FlutterG1(x: res.proof.a.x, y: res.proof.a.y, z: res.proof.a.z)
  let g2b = FlutterG2(x: res.proof.b.x, y: res.proof.b.y, z: res.proof.b.z)
  let g1c = FlutterG1(x: res.proof.c.x, y: res.proof.c.y, z: res.proof.c.z)
  let proof = FlutterGroth16Proof(
    a: g1a, b: g2b, c: g1c, `protocol`: res.proof.protocol, curve: res.proof.curve)
  let wrapped = FlutterGroth16ProofResult(proof: proof, inputs: res.inputs)
  return [
    "proof": [
      "a": ["x": wrapped.proof.a.x, "y": wrapped.proof.a.y, "z": wrapped.proof.a.z],
      "b": ["x": wrapped.proof.b.x, "y": wrapped.proof.b.y, "z": wrapped.proof.b.z],
      "c": ["x": wrapped.proof.c.x, "y": wrapped.proof.c.y, "z": wrapped.proof.c.z],
      "protocol": wrapped.proof.protocol,
      "curve": wrapped.proof.curve,
    ],
    "inputs": wrapped.inputs,
  ]
}

func convertGroth16ProofResult(proof: [String: Any]) -> Groth16ProofResult {
  let proofMap = proof["proof"] as! [String: Any]
  let aMap = proofMap["a"] as! [String: String]
  let g1a = G1(x: aMap["x"] ?? "0", y: aMap["y"] ?? "0", z: aMap["z"] ?? "1")
  let bMap = proofMap["b"] as! [String: [String]]
  let g2b = G2(
    x: bMap["x"] ?? ["1", "0"],
    y: bMap["y"] ?? ["1", "0"],
    z: bMap["z"] ?? ["1", "0"])
  let cMap = proofMap["c"] as! [String: String]
  let g1c = G1(x: cMap["x"] ?? "0", y: cMap["y"] ?? "0", z: cMap["z"] ?? "1")
  let groth16Proof = Groth16Proof(
    a: g1a, b: g2b, c: g1c,
    `protocol`: proofMap["protocol"] as! String,
    curve: proofMap["curve"] as! String)
  return Groth16ProofResult(proof: groth16Proof, inputs: proof["inputs"] as! [String])
}

// MARK: - Plugin

public class MoproFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mopro_flutter", binaryMessenger: registrar.messenger())
    let instance = MoproFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {

    // ==========================================================================
    // Groth16
    // ==========================================================================
    case "generateGroth16Proof":
      guard let args = call.arguments as? [String: Any],
            let zkeyPath = args["zkeyPath"] as? String,
            let inputs = args["inputs"] as? String,
            let proofLib = args["proofLib"] as? Int
      else {
        return result(FlutterError(
          code: "ARGUMENT_ERROR", message: "Missing arguments \(call.arguments ?? [:])", details: nil))
      }

      let resolvedZkeyPath = resolveBundlePath(assetPath: zkeyPath)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let moproProofLib: Groth16ProofLib = (proofLib == 0) ? .arkworks : .rapidsnark
          let proofResult = try generateGroth16Proof(
            zkeyPath: resolvedZkeyPath, circuitInputs: inputs, proofLib: moproProofLib)
          let resultMap = convertGroth16Proof(res: proofResult)
          DispatchQueue.main.async { result(resultMap) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROOF_GENERATION_ERROR",
              message: "Failed to generate proof",
              details: error.localizedDescription))
          }
        }
      }

    case "verifyGroth16Proof":
      guard let args = call.arguments as? [String: Any],
            let zkeyPath = args["zkeyPath"] as? String,
            let proof = args["proof"] as? [String: Any],
            let proofLib = args["proofLib"] as? Int
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing arguments", details: nil))
      }

      let resolvedZkeyPath = resolveBundlePath(assetPath: zkeyPath)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let moproProofLib: Groth16ProofLib = (proofLib == 0) ? .arkworks : .rapidsnark
          let groth16ProofResult = convertGroth16ProofResult(proof: proof)
          let valid = try verifyGroth16Proof(
            zkeyPath: resolvedZkeyPath, proofResult: groth16ProofResult, proofLib: moproProofLib)
          DispatchQueue.main.async { result(valid) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROOF_VERIFICATION_ERROR",
              message: "Failed to verify proof",
              details: error.localizedDescription))
          }
        }
      }

    // ==========================================================================
    // Barretenberg
    // ==========================================================================
    case "generateBarretenbergProof":
      guard let args = call.arguments as? [String: Any],
            let circuitPath = args["circuitPath"] as? String,
            let inputs = args["inputs"] as? [String],
            let onChain = args["onChain"] as? Bool,
            let vk = args["vk"] as? FlutterStandardTypedData,
            let lowMemoryMode = args["lowMemoryMode"] as? Bool
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing arguments", details: nil))
      }
      let srsPath = args["srsPath"] as? String

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let proofResult = try generateBarretenbergProof(
            circuitPath: circuitPath, srsPath: srsPath, inputs: inputs,
            onChain: onChain, vk: vk.data, lowMemoryMode: lowMemoryMode)
          DispatchQueue.main.async { result(proofResult) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROOF_GENERATION_ERROR",
              message: "Failed to generate proof",
              details: error.localizedDescription))
          }
        }
      }

    case "verifyBarretenbergProof":
      guard let args = call.arguments as? [String: Any],
            let circuitPath = args["circuitPath"] as? String,
            let proof = args["proof"] as? FlutterStandardTypedData,
            let onChain = args["onChain"] as? Bool,
            let vk = args["vk"] as? FlutterStandardTypedData,
            let lowMemoryMode = args["lowMemoryMode"] as? Bool
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing arguments", details: nil))
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let valid = try verifyBarretenbergProof(
            circuitPath: circuitPath, proof: proof.data,
            onChain: onChain, vk: vk.data, lowMemoryMode: lowMemoryMode)
          DispatchQueue.main.async { result(valid) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROOF_VERIFICATION_ERROR",
              message: "Failed to verify proof",
              details: error.localizedDescription))
          }
        }
      }

    case "getBarretenbergVerificationKey":
      guard let args = call.arguments as? [String: Any],
            let circuitPath = args["circuitPath"] as? String,
            let onChain = args["onChain"] as? Bool,
            let lowMemoryMode = args["lowMemoryMode"] as? Bool
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing arguments", details: nil))
      }
      let srsPath = args["srsPath"] as? String

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let vkResult = try getBarretenbergVerificationKey(
            circuitPath: circuitPath, srsPath: srsPath,
            onChain: onChain, lowMemoryMode: lowMemoryMode)
          DispatchQueue.main.async { result(vkResult) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "VK_GENERATION_ERROR",
              message: "Failed to generate verification key",
              details: error.localizedDescription))
          }
        }
      }

    // ==========================================================================
    // RISC0
    // ==========================================================================
    case "generateRisc0Proof":
      guard let args = call.arguments as? [String: Any],
            let input = args["input"] as? Int
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing input", details: nil))
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let res = try risc0Prove(input: UInt32(input))
          DispatchQueue.main.async {
            result(["receipt": FlutterStandardTypedData(bytes: Data(res.receipt))])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROOF_GENERATION_ERROR",
              message: "Failed to generate RISC0 proof",
              details: error.localizedDescription))
          }
        }
      }

    case "verifyRisc0Proof":
      guard let args = call.arguments as? [String: Any],
            let receiptBytes = args["receiptBytes"] as? FlutterStandardTypedData
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing receiptBytes", details: nil))
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let res = try risc0Verify(receiptBytes: [UInt8](receiptBytes.data))
          DispatchQueue.main.async {
            result([
              "isValid": res.isValid,
              "outputValue": Int(res.outputValue),
            ])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROOF_VERIFICATION_ERROR",
              message: "Failed to verify RISC0 proof",
              details: error.localizedDescription))
          }
        }
      }

    // ==========================================================================
    // Cairo-M
    // ==========================================================================
    case "generateCairoProof":
      guard let args = call.arguments as? [String: Any],
            let programJson = args["programJson"] as? String,
            let inputsJson = args["inputsJson"] as? String,
            let entrypoint = args["entrypoint"] as? String
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing arguments", details: nil))
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let proofOutput = try cairoProve(
            programJson: programJson, inputsJson: inputsJson, entrypoint: entrypoint)
          DispatchQueue.main.async {
            result(["proof": FlutterStandardTypedData(bytes: Data(proofOutput.proof))])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "CAIRO_PROOF_ERROR",
              message: "Failed to generate Cairo proof",
              details: error.localizedDescription))
          }
        }
      }

    case "verifyCairoProof":
      guard let args = call.arguments as? [String: Any],
            let proof = args["proof"] as? FlutterStandardTypedData
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing proof", details: nil))
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let verifyOutput = try cairoVerify(proof: [UInt8](proof.data))
          DispatchQueue.main.async {
            result(["is_valid": verifyOutput.isValid])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "CAIRO_VERIFY_ERROR",
              message: "Failed to verify Cairo proof",
              details: error.localizedDescription))
          }
        }
      }

    // ==========================================================================
    // ProveKit
    // ==========================================================================
    case "generateProveKitProof":
      guard let args = call.arguments as? [String: Any],
            let proverPath = args["proverPath"] as? String,
            let inputToml = args["inputToml"] as? String
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing arguments", details: nil))
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let proofOutput = try provekitProve(proverPath: proverPath, inputToml: inputToml)
          DispatchQueue.main.async {
            result(["proof": FlutterStandardTypedData(bytes: Data(proofOutput.proof))])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROVEKIT_PROOF_ERROR",
              message: "Failed to generate ProveKit proof",
              details: error.localizedDescription))
          }
        }
      }

    case "verifyProveKitProof":
      guard let args = call.arguments as? [String: Any],
            let verifierPath = args["verifierPath"] as? String,
            let proof = args["proof"] as? FlutterStandardTypedData
      else {
        return result(FlutterError(code: "ARGUMENT_ERROR", message: "Missing arguments", details: nil))
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let verifyOutput = try provekitVerify(verifierPath: verifierPath, proof: [UInt8](proof.data))
          DispatchQueue.main.async {
            result(["is_valid": verifyOutput.isValid])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "PROVEKIT_VERIFY_ERROR",
              message: "Failed to verify ProveKit proof",
              details: error.localizedDescription))
          }
        }
      }

    // ==========================================================================
    // Memory probe
    // ==========================================================================
    case "getIOSMemoryUsage":
      result(getMemoryUsage())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Helpers

  private func resolveBundlePath(assetPath: String) -> String {
    let key = FlutterDartProject.lookupKey(forAsset: assetPath)
    if let bundlePath = Bundle.main.path(forResource: key, ofType: nil) {
      return bundlePath
    }
    return assetPath
  }

  private func getMemoryUsage() -> [String: Int64] {
    var taskInfo = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    var usedMemory: Int64 = 0
    if kerr == KERN_SUCCESS {
      usedMemory = Int64(taskInfo.resident_size)
    }
    let totalMemory = Int64(ProcessInfo.processInfo.physicalMemory)
    return ["used": usedMemory, "total": totalMemory]
  }
}
