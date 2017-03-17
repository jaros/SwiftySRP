//
//  SRPBigIntImpl.swift
//  SwiftySRP
//
//  Created by Sergey A. Novitsky on 22/02/2017.
//  Copyright © 2017 Flock of Files. All rights reserved.
//

import Foundation
import BigInt

/// Implementation of the SRP protocol. Although it's primarily intended to be used on the client side, it includes the server side methods
/// as well (for testing purposes).
public struct SRPBigIntImpl: SRPProtocol
{
    /// SRP configuration. Defines the prime N and generator g to be used, and also the relevant hashing functions.
    public var configuration: SRPConfiguration
    
    /// Generate client credentials (parameters x, a, and A) from the SRP salt, user name (I), and password (p)
    ///
    /// - Parameters:
    ///   - s: SRP salt
    ///   - I: User name
    ///   - p: Password
    /// - Returns: SRP data with parameters x, a, and A populated.
    /// - Throws: SRPError if input parameters or configuration are not valid.
    public func generateClientCredentials(s: Data, I: Data, p: Data) throws -> SRPData
    {
        // TODO: There may be more stringent requirements about salt.
        try configuration.validate()
        guard !s.isEmpty else { throw SRPError.invalidSalt }
        guard !I.isEmpty else { throw SRPError.invalidUserName }
        guard !p.isEmpty else { throw SRPError.invalidPassword }
        
        let value_x = x(s: s, I: I, p: p)
        let value_a = configuration.uint_a()
        
        // A = g^a
        let value_A = configuration.uint_g.power(value_a, modulus: configuration.uint_N)
        
        return SRPDataBigIntImpl(x: value_x, a: value_a, A: value_A)
    }
    
    
    /// Generate the server side SRP parameters. This method normally will NOT be used by the client.
    /// It's included here for testing purposes.
    /// - Parameter verifier: SRP verifier received from the client.
    /// - Returns: SRP data with parameters v, k, b, and B populated.
    /// - Throws: SRPError if the verifier or configuration is invalid.
    public func generateServerCredentials(verifier: Data) throws -> SRPData
    {
        guard !verifier.isEmpty else { throw SRPError.invalidVerifier }
        try configuration.validate()
        let N = configuration.uint_N
        
        let v = BigUInt(verifier)
        let k = hashPaddedPair(digest: configuration.digest, N: N, n1: N, n2: configuration.uint_g)
        let b = configuration.uint_b()
        
        // B = kv + g^b
        let B = (((k * v) % N) + configuration.uint_g.power(b, modulus: N)) % N
        
        return SRPDataBigIntImpl(v:v, k:k, b:b, B:B)
    }
    
    
    /// Compute the verifier and client credentials.
    ///
    /// - Parameters:
    ///   - s: SRP salt
    ///   - I: User name
    ///   - p: Password
    /// - Returns: SRPData with parameters v, x, a, and A populated.
    /// - Throws: SRPError if input parameters or configuration are not valid.
    public func verifier(s: Data, I: Data,  p: Data) throws -> SRPData
    {
        // let valueX = x(s:s, I:I, p:p)
        var srpData = try generateClientCredentials(s: s, I: I, p: p)
        
        srpData.uint_v = configuration.uint_g.power(srpData.uint_x, modulus:configuration.uint_N)
        
        return srpData
    }
    
    
    /// Calculate the shared secret on the client side: S = (B - kg^x) ^ (a + ux)
    ///
    /// - Parameter srpData: SRP data to use in the calculation.
    ///   Must have the following parameters populated and valid: B (received from the server), A (computed previously), a, x
    /// - Returns: SRPData with parameter S populated
    /// - Throws: SRPError if some of the input parameters is not set or invalid.
    public func calculateClientSecret(srpData: SRPData) throws -> SRPData
    {
        try configuration.validate()
        let N = configuration.uint_N
        var resultData = srpData
        guard (resultData.uint_A % N) > 0 else { throw SRPError.invalidClientPublicValue }
        guard (resultData.uint_B % N) > 0 else { throw SRPError.invalidServerPublicValue }
        guard resultData.uint_a > 0 else { throw SRPError.invalidClientPrivateValue }
        guard resultData.uint_x > 0 else { throw SRPError.invalidPasswordHash }
        
        resultData.uint_u = hashPaddedPair(digest: configuration.digest, N: N, n1: resultData.uint_A, n2: resultData.uint_B)
        resultData.uint_k = hashPaddedPair(digest: configuration.digest, N: N, n1: N, n2: configuration.uint_g)
        
        let exp = ((resultData.uint_u * resultData.uint_x) + resultData.uint_a)
        
        let tmp = (configuration.uint_g.power(resultData.uint_x, modulus: N) * resultData.uint_k) % N

        // Add N to avoid the possible negative number.
        resultData.uint_clientS = ((resultData.uint_B + N - tmp) % N).power(exp, modulus: N)
        
        return resultData
    }
    
    
    /// Calculate the shared secret on the server side: S = (Av^u) ^ b
    ///
    /// - Parameter srpData: SRPData with the following parameters populated: A, v, b, B
    /// - Returns: SRPData with the computed u and serverS
    /// - Throws: SRPError if some of the required parameters are invalid.
    public func calculateServerSecret(srpData: SRPData) throws -> SRPData
    {
        try configuration.validate()
        let N = configuration.uint_N

        var resultData = srpData
        guard (resultData.uint_A % N) > 0 else { throw SRPError.invalidClientPublicValue }
        guard (resultData.uint_B % N) > 0 else { throw SRPError.invalidServerPublicValue }
        guard resultData.uint_b > 0 else { throw SRPError.invalidServerPrivateValue }
        guard resultData.uint_v > 0 else { throw SRPError.invalidVerifier }
        
        resultData.uint_u = hashPaddedPair(digest: configuration.digest, N: N, n1: resultData.uint_A, n2: resultData.uint_B)
        
        // S = (Av^u) ^ b
        resultData.uint_serverS = ((resultData.uint_A * resultData.uint_v.power(resultData.uint_u, modulus: N)) % N).power(resultData.uint_b, modulus: N)
        
        return resultData
    }
    
    /// Compute the client evidence message.
    /// NOTE: This is different from the spec. above and is done the BouncyCastle way:
    /// M = H( pA | pB | pS), where pA, pB, and pS - padded values of A, B, and S
    /// - Parameter srpData: SRP data to use in the calculation.
    ///   Must have the following fields populated:
    ///   - a: Private ephemeral value a (per spec. above)
    ///   - A: Public ephemeral value A (per spec. above)
    ///   - x: Identity hash (computed the BouncyCastle way)
    ///   - B: Server public ephemeral value B (per spec. above)
    /// - Returns: SRPData with the client evidence message populated.
    /// - Throws: SRPError if some of the required parameters are invalid.
    public func clientEvidenceMessage(srpData: SRPData) throws -> SRPData
    {
        try configuration.validate()
        let N = configuration.uint_N

        var resultData = srpData
        
        guard (resultData.uint_A % N) > 0 else { throw SRPError.invalidClientPublicValue }
        guard (resultData.uint_B % N) > 0 else { throw SRPError.invalidServerPublicValue }
        
        if resultData.uint_clientS == 0
        {
            resultData = try calculateClientSecret(srpData: resultData)
        }
        
        resultData.uint_clientM = hashPaddedTriplet(digest: configuration.digest, N: N, n1: resultData.uint_A, n2: resultData.uint_B, n3: resultData.uint_clientS)
        return resultData
    }
    
    
    /// Compute the server evidence message.
    /// NOTE: This is different from the spec above and is done the BouncyCastle way:
    /// M = H( pA | pMc | pS), where pA is the padded A value; pMc is the padded client evidence message, and pS is the padded shared secret.
    /// - Parameter srpData: SRP Data with the following fields populated:
    ///   - A: Client value A
    ///   - v: Password verifier v (per spec above)
    ///   - b: Private ephemeral value b
    ///   - B: Public ephemeral value B
    ///   - clientM: Client evidence message
    /// - Returns: SRPData with the computed server evidence message field populated.
    /// - Throws: SRPError if some of the required parameters are invalid.
    public func serverEvidenceMessage(srpData: SRPData) throws -> SRPData
    {
        try configuration.validate()
        let N = configuration.uint_N

        var resultData = srpData
        guard (resultData.uint_A % N) > 0 else { throw SRPError.invalidClientPublicValue }
        guard (resultData.uint_B % N) > 0 else { throw SRPError.invalidServerPublicValue }
        if resultData.uint_serverS == 0
        {
            resultData = try calculateServerSecret(srpData: resultData)
        }
        
        resultData.uint_serverM = hashPaddedTriplet(digest: configuration.digest,
                                               N: N,
                                               n1: resultData.uint_A,
                                               n2: resultData.uint_clientM,
                                               n3: resultData.uint_serverS)
        
        return resultData
    }
    
    
    /// Verify the client evidence message (received from the client)
    ///
    /// - Parameter srpData: SRPData with the following fields populated: A, B, clientM, serverS
    /// - Throws: SRPError in case verification fails or when some of the required parameters are invalid.
    public func verifyClientEvidenceMessage(srpData: SRPData) throws
    {
        try configuration.validate()
        let N = configuration.uint_N
        let resultData = srpData
        guard resultData.uint_clientM > 0 else { throw SRPError.invalidClientEvidenceMessage }
        guard (resultData.uint_A % N) > 0 else { throw SRPError.invalidClientPublicValue }
        guard (resultData.uint_B % N) > 0 else { throw SRPError.invalidServerPublicValue }
        guard resultData.uint_serverS > 0 else { throw SRPError.invalidServerSharedSecret }
        
        let M = hashPaddedTriplet(digest: configuration.digest, N: N, n1: resultData.uint_A, n2: resultData.uint_B, n3: resultData.uint_serverS)
        guard (M == resultData.uint_clientM) else { throw SRPError.invalidClientEvidenceMessage }
    }
    
    
    /// Verify the server evidence message (received from the server)
    ///
    /// - Parameter srpData: SRPData with the following fields populated: serverM, clientM, A, clientS
    /// - Throws: SRPError if verification fails or if some of the input parameters is invalid.
    public func verifyServerEvidenceMessage(srpData: SRPData) throws
    {
        try configuration.validate()
        let N = configuration.uint_N
        let resultData = srpData
        guard resultData.uint_serverM > 0 else { throw SRPError.invalidServerEvidenceMessage }
        guard resultData.uint_clientM > 0 else { throw SRPError.invalidClientEvidenceMessage }
        guard (resultData.uint_A % N) > 0 else { throw SRPError.invalidClientPublicValue }
        guard resultData.uint_clientS > 0 else { throw SRPError.invalidClientSharedSecret }
        
        let M = hashPaddedTriplet(digest: configuration.digest, N: N, n1: resultData.uint_A, n2: resultData.uint_clientM, n3: resultData.uint_clientS)
        guard (M == resultData.uint_serverM) else { throw SRPError.invalidServerEvidenceMessage }
    }
    
    
    /// Calculate the shared key (client side) in the standard way: sharedKey = H(clientS)
    ///
    /// - Parameter srpData: SRPData with clientS populated.
    /// - Returns: Shared key
    /// - Throws: SRPError if some of the required parameters is invalid.
    public func calculateClientSharedKey(srpData: SRPData) throws -> Data
    {
        try configuration.validate()
        let resultData = srpData
        guard resultData.uint_clientS > 0 else { throw SRPError.invalidClientSharedSecret }
        let padLength = (configuration.uint_N.width + 7) / 8
        let paddedS = pad(resultData.uint_clientS.serialize(), to: padLength)
        let hash = configuration.digest(paddedS)
        
        return hash
    }
    
    /// Calculate the shared key (server side) in the standard way: sharedKey = H(serverS)
    ///
    /// - Parameter srpData: SRPData with serverS populated.
    /// - Returns: Shared key
    /// - Throws: SRPError if some of the required parameters is invalid.
    public func calculateServerSharedKey(srpData: SRPData) throws -> Data
    {
        try configuration.validate()
        let resultData = srpData
        guard resultData.uint_serverS > 0 else { throw SRPError.invalidServerSharedSecret }
        let padLength = (configuration.uint_N.width + 7) / 8
        let paddedS = pad(resultData.uint_clientS.serialize(), to: padLength)
        let hash = configuration.digest(paddedS)
        
        return hash
    }
    
    /// Calculate the shared key (client side) by using HMAC: sharedKey = HMAC(salt, clientS)
    /// This version can be used to derive multiple shared keys from the same shared secret (by using different salts)
    /// - Parameter srpData: SRPData with clientS populated.
    /// - Returns: Shared key
    /// - Throws: SRPError if some of the required parameters is invalid.
    public func calculateClientSharedKey(srpData: SRPData, salt: Data) throws -> Data
    {
        try configuration.validate()
        let resultData = srpData
        return configuration.hmac(salt, resultData.uint_clientS.serialize())
    }
    
    /// Calculate the shared key (server side) by using HMAC: sharedKey = HMAC(salt, clientS)
    /// This version can be used to derive multiple shared keys from the same shared secret (by using different salts)
    /// - Parameter srpData: SRPData with clientS populated.
    /// - Returns: Shared key
    /// - Throws: SRPError if some of the required parameters is invalid.
    public func calculateServerSharedKey(srpData: SRPData, salt: Data) throws -> Data
    {
        try configuration.validate()
        let resultData = srpData
        return configuration.hmac(salt, resultData.uint_serverS.serialize())
    }
    
    
    /// Helper method to concatenate, pad, and hash two values.
    ///
    /// - Parameters:
    ///   - digest: The hash function to be used.
    ///   - N: Modulus; values are padded to the byte size of the modulus
    ///   - n1: First value
    ///   - n2: Second value
    /// - Returns: Result of hashing.
    internal func hashPaddedPair(digest: DigestFunc, N: BigUInt, n1: BigUInt, n2: BigUInt) -> BigUInt
    {
        let padLength = (N.width + 7) / 8
        
        let paddedN1 = pad(n1.serialize(), to: padLength)
        let paddedN2 = pad(n2.serialize(), to: padLength)
        var dataToHash = Data(capacity: paddedN1.count + paddedN2.count)
        dataToHash.append(paddedN1)
        dataToHash.append(paddedN2)
        
        let hash = digest(dataToHash)
        
        return BigUInt(hash) % N
    }
    
    
    /// Helper method to concatenate, pad, and hash three values.
    ///
    /// - Parameters:
    ///   - digest: The hash function to be used.
    ///   - N: Modulus; values are padded to the byte size of the modulus.
    ///   - n1: First value
    ///   - n2: Second value
    ///   - n3: Third value
    /// - Returns: Result of hashing.
    internal func hashPaddedTriplet(digest: DigestFunc, N: BigUInt, n1: BigUInt, n2: BigUInt, n3: BigUInt) -> BigUInt
    {
        let padLength = (N.width + 7) / 8
        
        let paddedN1 = pad(n1.serialize(), to: padLength)
        let paddedN2 = pad(n2.serialize(), to: padLength)
        let paddedN3 = pad(n3.serialize(), to: padLength)
        var dataToHash = Data(capacity: paddedN1.count + paddedN2.count + paddedN3.count)
        dataToHash.append(paddedN1)
        dataToHash.append(paddedN2)
        dataToHash.append(paddedN3)
        let hash = digest(dataToHash)
        
        return BigUInt(hash) % N
    }
    
    
    /// Pad the given data with zeroes to the given byte size
    ///
    /// - Parameters:
    ///   - data: Data to pad
    ///   - length: Desired byte length
    /// - Returns: Result of the padding.
    internal func pad(_ data: Data, to length: Int) -> Data
    {
        if data.count >= length
        {
            return data
        }
        
        var padded = Data(count: length - data.count)
        padded.append(data)
        return padded
    }
    
    
    /// Calculate the SRP parameter x the BouncyCastle way: x = H(s | H(I | ":" | p))
    /// | stands for concatenation
    /// - Parameters:
    ///   - s: SRP salt
    ///   - I: User name
    ///   - p: password
    /// - Returns: SRP value x calculated as x = H(s | H(I | ":" | p)) (where H is the configured hash function)
    internal func x(s: Data, I: Data,  p: Data) -> BigUInt
    {
        var identityData = Data(capacity: I.count + 1 + p.count)
        
        identityData.append(I)
        identityData.append(":".data(using: .utf8)!)
        identityData.append(p)
        
        let identityHash = configuration.digest(identityData)
        
        var xData = Data(capacity: s.count + identityHash.count)
        
        xData.append(s)
        xData.append(identityHash)
        
        let xHash = configuration.digest(xData)
        let x = BigUInt(xHash) % configuration.uint_N
        
        return x
    }
}

