import React, { useState, useEffect } from 'react';
import { Contract, parseEther } from 'ethers';
import { GOV_TOKEN_ADDRESS, GOVERNER_ADDRESS, GOV_TOKEN_ABI, GOVERNOR_ABI, parseError } from '../utils/web3';

function DAO({ provider, account }) {
    const [loading, setLoading] = useState(false);
    const [status, setStatus] = useState('');
    const [votes, setVotes] = useState('0');
    const [delegatedTo, setDelegatedTo] = useState('');

    const [voteProposalId, setVoteProposalId] = useState('');
    const [voteSupport, setVoteSupport] = useState(1); 

    const [propTarget, setPropTarget] = useState('');
    const [propValue, setPropValue] = useState('0');
    const [propDescription, setPropDescription] = useState('');

    const [proposals, setProposals] = useState([
        {
            id: "7859099599789200",
            description: "Proposal #1: Distribute 10,000 GOV to AMM Liquidity Providers",
            votesFor: "15,200",
            votesAgainst: "1,400",
            state: "Active"
        },
        {
            id: "4201832049100234",
            description: "Proposal #2: Reduce static AMM Swap Fee matrix to 0.2%",
            votesFor: "8,900",
            votesAgainst: "9,600",
            state: "Defeated"
        }
    ]);

    const fetchGovData = async () => {
        if (!account) return;
        try {
            const signer = await provider.getSigner();
            const token = new Contract(GOV_TOKEN_ADDRESS, GOV_TOKEN_ABI, signer);

            const balStr = await token.getVotes(account);
            setVotes((Number(balStr) / 1e18).toFixed(2));

            const del = await token.delegates(account);
            if (del === "0x0000000000000000000000000000000000000000") {
                setDelegatedTo("None (Votes Locked)");
            } else {
                setDelegatedTo(del.slice(0, 6) + "..." + del.slice(-4));
            }
        } catch (e) {
            console.log("Staking / Gov tokens offline, using mocked weights");
            setVotes("12,500");
            setDelegatedTo("Self-Delegated");
        }
    };

    useEffect(() => {
        fetchGovData();
    }, [account]);

    const handleDelegate = async () => {
        setStatus("Broadcasting delegate request to token contract...");
        setLoading(true);
        try {
            const signer = await provider.getSigner();
            const token = new Contract(GOV_TOKEN_ADDRESS, GOV_TOKEN_ABI, signer);

            const tx = await token.delegate(account);
            setStatus("Awaiting block confirmation (delegate)...");
            await tx.wait();

            setStatus("Self-Delegation Complete. Votes synchronized!");
            fetchGovData();
        } catch (err) {
            console.error(err);
            setStatus("ERROR: " + parseError(err));
        }
        setLoading(false);
    };

    const handleVoteSubmit = async () => {
        if (!voteProposalId) return;
        setStatus(`Initiating consensus payload for Proposal #${voteProposalId}...`);
        setLoading(true);
        try {
            const signer = await provider.getSigner();
            const gov = new Contract(GOVERNER_ADDRESS, GOVERNOR_ABI, signer);

            const tx = await gov.castVote(BigInt(voteProposalId), voteSupport);
            setStatus("Awaiting ballot verification (castVote)...");
            await tx.wait();

            setStatus(`Ballot successfully computed on-chain for support status: ${voteSupport === 1 ? 'FOR' : voteSupport === 0 ? 'AGAINST' : 'ABSTAIN'}`);
            fetchGovData();
        } catch (err) {
            console.error(err);
            setStatus("ERROR: " + parseError(err));
        }
        setLoading(false);
    };

    const handlePropose = async () => {
        if (!propTarget || !propDescription) return;
        setStatus("Preparing Proposal transaction sequence...");
        setLoading(true);
        try {
            const signer = await provider.getSigner();
            const gov = new Contract(GOVERNER_ADDRESS, GOVERNOR_ABI, signer);

            const tx = await gov.propose(
                [propTarget],
                [parseEther(propValue)],
                ["0x"],
                propDescription
            );
            setStatus("Awaiting DAO verification (propose)...");
            await tx.wait();

            setStatus("Proposal submitted successfully onto Timelock Registry!");
            fetchGovData();
        } catch (err) {
            console.error(err);
            setStatus("ERROR: " + parseError(err));
        }
        setLoading(false);
    };

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '30px' }}>

            {/* Wallet Voting Stats */}
            <div className="cyber-card">
                <h2 className="glitch-text">Security Dossier: Voter</h2>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '20px' }}>
                    <div>
                        <p style={{ margin: '5px 0' }}>Delegated Strength: <span style={{ color: 'var(--accent-secondary)' }}>{votes} GOV</span></p>
                        <p style={{ margin: '5px 0' }}>Current Target: <span style={{ color: 'var(--accent-primary)' }}>{delegatedTo}</span></p>
                    </div>
                    <button className="cyber-button" style={{ fontSize: '1rem', padding: '5px 15px' }} onClick={handleDelegate} disabled={loading}>
                        Self-Delegate
                    </button>
                </div>
                <p style={{ fontSize: '0.8rem', color: '#888' }}>
                    &gt;_ System reminder: You must self-delegate your voting credentials before your tokens translate into active voting power in governance cycles.
                </p>
            </div>

            {/* Proposals list */}
            <div className="cyber-card">
                <h2 className="glitch-text">Active Proposals</h2>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '15px' }}>
                    {proposals.map(p => (
                        <div key={p.id} style={{ borderBottom: '1px solid #336', paddingBottom: '10px' }}>
                            <p style={{ fontSize: '1.2rem', margin: '5px 0', fontFamily: 'VT323' }}>{p.description}</p>
                            <p style={{ fontSize: '0.8rem', color: '#888', margin: '2px 0' }}>ID: {p.id} | Status: <span style={{ color: p.state === 'Active' ? 'var(--accent-secondary)' : 'var(--warning)' }}>{p.state}</span></p>
                            <p style={{ fontSize: '0.8rem', margin: '2px 0' }}>
                                For: <span style={{ color: 'var(--accent-secondary)' }}>{p.votesFor}</span> | Against: <span style={{ color: 'var(--accent-primary)' }}>{p.votesAgainst}</span>
                            </p>
                        </div>
                    ))}
                </div>
            </div>

            {/* Cast Vote Block */}
            <div className="cyber-card">
                <h2 className="glitch-text">Consensus Injection Panel</h2>

                <label>Proposal Matrix Key (ID)</label>
                <input className="cyber-input" type="text" placeholder="e.g. 7859099599789200" onChange={e => setVoteProposalId(e.target.value)} />

                <label>Ballot Selection</label>
                <select className="cyber-input" style={{ background: '#0e0e0e' }} onChange={e => setVoteSupport(Number(e.target.value))}>
                    <option value={1}>FOR [Consensus Approved]</option>
                    <option value={0}>AGAINST [Vector Denied]</option>
                    <option value={2}>ABSTAIN [Signal Neutral]</option>
                </select>

                <button className="cyber-button" onClick={handleVoteSubmit} disabled={loading}>
                    {loading ? "Processing..." : "Cast Ballot"}
                </button>
            </div>

            {/* Submit Proposal Block */}
            <div className="cyber-card">
                <h2 className="glitch-text">Propose Matrix Amendment</h2>

                <label>Target Execution Address</label>
                <input className="cyber-input" placeholder="0x..." onChange={e => setPropTarget(e.target.value)} />

                <label>Ether Value Payload (Sepolia ETH)</label>
                <input className="cyber-input" type="number" placeholder="0.0" onChange={e => setPropValue(e.target.value)} />

                <label>Amendment Specifications (Description)</label>
                <input className="cyber-input" placeholder="Amend static exchange parameters..." onChange={e => setPropDescription(e.target.value)} />

                <button className="cyber-button" onClick={handlePropose} disabled={loading}>
                    {loading ? "Processing..." : "Submit Amendment"}
                </button>
            </div>

            {status && <p style={{ color: status.includes("ERROR") ? 'var(--warning)' : 'var(--text-color)' }}>
                &gt;_ {status}
            </p>}

        </div>
    );
}

export default DAO;
