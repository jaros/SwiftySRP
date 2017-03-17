//
//  SRPDataIMathImpl.swift
//  SwiftySRP
//
//  Created by Sergey A. Novitsky on 16/03/2017.
//  Copyright © 2017 Flock of Files. All rights reserved.
//

import Foundation

struct SRPDataIMathImpl: SRPData
{
    /// Password hash 'x' as BigUInt (see SRP spec. in SRPProtocol.swift)
    var _x = SRPMpzT()
    
    /// Client private value 'a' as BigUInt (see SRP spec. in SRPProtocol.swift)
    var _a = SRPMpzT()
    
    /// Client public value 'A' as BigUInt (see SRP spec. in SRPProtocol.swift)
    var _A = SRPMpzT()
    
    /// Client evidence message, computed as: M = H( pA | pB | pS), where pA, pB, and pS - padded values of A, B, and S (see SRP spec. in SRPProtocol.swift)
    var _clientM = SRPMpzT()
    
    /// Server evidence message, computed as: M = H( pA | pMc | pS), where pA is the padded A value; pMc is the padded client evidence message, and pS is the padded shared secret. (see SRP spec. in SRPProtocol.swift)
    var _serverM = SRPMpzT()
    
    // Common data
    /// SRP Verifier 'v' (see SRP spec. in SRPProtocol.swift)
    var _v = SRPMpzT()
    
    /// scrambler u = H(A, B) (see SRP spec. in SRPProtocol.swift)
    var _u = SRPMpzT()
    
    /// Shared secret. Computed on the client as: S = (B - kg^x) ^ (a + ux) (see SRP spec. in SRPProtocol.swift)
    var _clientS = SRPMpzT()
    
    /// Shared secret. Computed on the server as: S = (Av^u) ^ b (see SRP spec. in SRPProtocol.swift)
    var _serverS = SRPMpzT()
    
    // Server specific data
    
    /// Multiplier 'k'. Computed as: k = H(N, g) (see SRP spec. in SRPProtocol.swift)
    var _k = SRPMpzT()
    
    /// Server private ephemeral value 'b' (see SRP spec. in SRPProtocol.swift)
    var _b = SRPMpzT()
    
    /// Server public ephemeral value 'B' (see SRP spec. in SRPProtocol.swift)
    var _B = SRPMpzT()
    
    /// Initializer to be used for client size data.
    ///
    /// - Parameters:
    ///   - x: Salted password hash (= H(s, p))
    ///   - a: Private ephemeral value 'a' (per SRP spec. above)
    ///   - A: Public ephemeral value 'A' (per SRP spec. above)
    init(x: SRPMpzT, a: SRPMpzT, A: SRPMpzT)
    {
        // Actually copy the values.
        _x = SRPMpzT(x)
        _a = SRPMpzT(a)
        _A = SRPMpzT(A)
    }
    
    
    /// Initializer to be used for the server side data.
    ///
    /// - Parameters:
    ///   - v: SRP verifier (received from the client)
    ///   - k: Parameter 'k' (per SRP spec. above)
    ///   - b: Private ephemeral value 'b' (per SRP spec. above)
    ///   - B: Public ephemeral value 'B' (per SRP spec. above)
    init(v: SRPMpzT, k: SRPMpzT, b: SRPMpzT, B: SRPMpzT)
    {
        _v = v
        _k = k
        _b = b
        _B = B
    }

    /// Client public value 'A' (see the spec. above)
    var clientPublicValue: Data {
        get {
            return _A.serialize()
        }
        set {
            _A = SRPMpzT(newValue)
        }
    }
    
    /// Client private value 'a' (see the spec. above)
    public var clientPrivateValue: Data {
        get {
            return _a.serialize()
        }
        set {
            _a = SRPMpzT(newValue)
        }
    }
    
    
    /// Client evidence message, computed as: M = H( pA | pB | pS), where pA, pB, and pS - padded values of A, B, and S
    var clientEvidenceMessage: Data {
        get {
            return _clientM.serialize()
        }
        set {
            _clientM = SRPMpzT(newValue)
        }
    }
    
    /// Password hash (see the spec. above)
    public var passwordHash: Data {
        get {
            return _x.serialize()
        }
        
        set {
            _x = SRPMpzT(newValue)
        }
    }
    
    /// Scrambler u
    public var scrambler: Data {
        get {
            return _u.serialize()
        }
        set {
            _u = SRPMpzT(newValue)
        }
    }
    
    /// Client secret 'S' (see SRP spec. in SRPProtocol.swift)
    public var clientSecret: Data {
        get {
            return _clientS.serialize()
        }
        set {
            _clientS = SRPMpzT(newValue)
        }
    }
    
    /// SRP Verifier 'v' (see SRP spec. in SRPProtocol.swift)
    var verifier: Data {
        get {
            return _v.serialize()
        }
        set {
            _v = SRPMpzT(newValue)
        }
    }
    
    /// Server public value 'B' (see SRP spec. in SRPProtocol.swift)
    var serverPublicValue: Data {
        get {
            return _B.serialize()
        }
        
        set {
            _B = SRPMpzT(newValue)
        }
    }
    
    /// Server private value 'b' (see SRP spec. in SRPProtocol.swift)
    public var serverPrivateValue: Data {
        get {
            return _b.serialize()
        }
        set {
            _b = SRPMpzT(newValue)
        }
    }
    
    /// Server shared secret 'S' (see SRP spec. in SRPProtocol.swift)
    public var serverSecret: Data {
        get {
            return _serverS.serialize()
        }
        set {
            _serverS = SRPMpzT(newValue)
        }
    }
    
    // Multiplier parameter 'k' (see SRP spec. in SRPProtocol.swift)
    public var multiplier: Data {
        get {
            return _k.serialize()
        }
        set {
            _k = SRPMpzT(newValue)
        }
    }
    
    /// Server evidence message, computed as: M = H( pA | pMc | pS), where pA is the padded A value; pMc is the padded client evidence message, and pS is the padded shared secret. (see SRP spec. in SRPProtocol.swift)
    var serverEvidenceMessage: Data {
        get {
            return _serverM.serialize()
        }
        
        set {
            _serverM = SRPMpzT(newValue)
        }
    }

}
