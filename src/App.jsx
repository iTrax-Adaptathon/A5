import { useEffect, useMemo, useState } from 'react'
import { Link, Navigate, Route, Routes, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { isConfigured, supabase } from './supabase'

const categories = ['All', 'Fitness', 'Learning', 'Environment', 'Creativity', 'Wellbeing', 'Community']
const difficulties = ['All', 'easy', 'medium', 'hard']
const scoreLabels = [['completion_score', 'Completion'], ['quality_score', 'Quality'], ['verification_score', 'Verification'], ['peer_score', 'Peer review']]

function formatDate(date) { return date ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(date)) : 'No end date' }
function errorText(error) { return error?.message || 'Something went wrong. Please try again.' }

function useAuth() {
  const [session, setSession] = useState(null)
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    if (!supabase) return setLoading(false)
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setLoading(false) })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => setSession(nextSession))
    return () => listener.subscription.unsubscribe()
  }, [])
  return { session, loading }
}

async function ensureProfile(user) {
  const fallbackName = user.user_metadata?.name || user.email?.split('@')[0] || 'Community member'
  const { error } = await supabase.from('profiles').upsert({ id: user.id, name: fallbackName }, { onConflict: 'id', ignoreDuplicates: true })
  if (error) throw error
}

function Shell({ session, children }) {
  const navigate = useNavigate()
  async function signOut() { await supabase.auth.signOut(); navigate('/auth') }
  return <div className="app-shell">
    <header className="topbar"><Link className="brand" to="/">Common Ground</Link>
      {session && <nav><Link to="/">Explore</Link><Link to="/create">Create</Link><Link to="/leaderboard">Leaderboard</Link><Link to="/profile">Profile</Link><button className="link-button" onClick={signOut}>Sign out</button></nav>}
    </header>
    <main>{children}</main>
  </div>
}

function AuthPage({ onReady }) {
  const [mode, setMode] = useState('login'); const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [name, setName] = useState(''); const [message, setMessage] = useState(''); const [busy, setBusy] = useState(false)
  async function submit(event) {
    event.preventDefault(); setBusy(true); setMessage('')
    const result = mode === 'login' ? await supabase.auth.signInWithPassword({ email, password }) : await supabase.auth.signUp({ email, password, options: { data: { name } } })
    setBusy(false)
    if (result.error) return setMessage(errorText(result.error))
    if (result.data.user && result.data.session) { await ensureProfile(result.data.user); onReady() }
    else setMessage('Check your email to confirm your account, then sign in.')
  }
  return <section className="auth-page"><div className="auth-card"><p className="eyebrow">COMMUNITY CHALLENGES</p><h1>Make progress together.</h1><p className="muted">Create short, meaningful challenges. Evaluation is based on evidence and rubrics—not likes.</p>
    <div className="tab-row"><button className={mode === 'login' ? 'active' : ''} onClick={() => setMode('login')}>Log in</button><button className={mode === 'signup' ? 'active' : ''} onClick={() => setMode('signup')}>Create account</button></div>
    <form onSubmit={submit}>{mode === 'signup' && <label>Name<input required value={name} onChange={e => setName(e.target.value)} /></label>}<label>Email<input required type="email" value={email} onChange={e => setEmail(e.target.value)} /></label><label>Password<input required minLength="6" type="password" value={password} onChange={e => setPassword(e.target.value)} /></label>{message && <p className="notice">{message}</p>}<button className="primary full" disabled={busy}>{busy ? 'Please wait…' : mode === 'login' ? 'Log in' : 'Create account'}</button></form>
  </div></section>
}

function ChallengeCard({ challenge, member, onJoin }) { return <article className="card challenge-card"><div className="card-top"><span className="tag">{challenge.category || 'General'}</span><span className={'difficulty ' + (challenge.difficulty || 'medium')}>{challenge.difficulty || 'medium'}</span></div><h3>{challenge.title}</h3><p>{challenge.description || 'A community challenge waiting for its first story.'}</p><div className="card-footer"><span>Ends {formatDate(challenge.end_date)}</span><div>{member ? <Link className="secondary" to={`/challenge/${challenge.id}`}>View progress</Link> : <button className="secondary" onClick={() => onJoin(challenge.id)}>Join challenge</button>}</div></div></article> }

function Browse({ user }) {
  const [challenges, setChallenges] = useState([]); const [joined, setJoined] = useState(new Set()); const [category, setCategory] = useState('All'); const [difficulty, setDifficulty] = useState('All'); const [message, setMessage] = useState(''); const [loading, setLoading] = useState(true)
  async function load() { setLoading(true); const [challengeResult, membershipResult] = await Promise.all([supabase.from('challenges').select('*').in('status', ['open', 'active']).order('created_at', { ascending: false }), supabase.from('participants').select('challenge_id').eq('user_id', user.id)]); if (challengeResult.error) setMessage(errorText(challengeResult.error)); else setChallenges(challengeResult.data); if (!membershipResult.error) setJoined(new Set(membershipResult.data.map(row => row.challenge_id))); setLoading(false) }
  useEffect(() => { load() }, [user.id])
  const visible = useMemo(() => challenges.filter(c => (category === 'All' || c.category === category) && (difficulty === 'All' || c.difficulty === difficulty)), [challenges, category, difficulty])
  async function join(challengeId) { const { error } = await supabase.from('participants').insert({ challenge_id: challengeId, user_id: user.id }); if (error) setMessage(errorText(error)); else { setJoined(old => new Set([...old, challengeId])); setMessage('You joined the challenge. Good luck!') } }
  return <><section className="hero"><div><p className="eyebrow">FIND YOUR NEXT WIN</p><h1>Small actions, shared momentum.</h1><p>Join a challenge, document your work, and receive meaningful feedback.</p></div><Link className="primary" to="/create">Create a challenge</Link></section><section className="filters"><label>Category<select value={category} onChange={e => setCategory(e.target.value)}>{categories.map(x => <option key={x}>{x}</option>)}</select></label><label>Difficulty<select value={difficulty} onChange={e => setDifficulty(e.target.value)}>{difficulties.map(x => <option key={x} value={x}>{x === 'All' ? x : x[0].toUpperCase() + x.slice(1)}</option>)}</select></label></section>{message && <p className="notice">{message}</p>}<section className="grid">{loading ? <p>Loading challenges…</p> : visible.length ? visible.map(c => <ChallengeCard key={c.id} challenge={c} member={joined.has(c.id)} onJoin={join} />) : <div className="empty">No challenges match these filters yet.</div>}</section></>
}

function CreateChallenge({ user }) {
  const navigate = useNavigate(); const [form, setForm] = useState({ title: '', description: '', category: 'Community', difficulty: 'medium', start_date: '', end_date: '' }); const [error, setError] = useState(''); const [busy, setBusy] = useState(false)
  const set = key => event => setForm(old => ({ ...old, [key]: event.target.value }))
  async function submit(event) { event.preventDefault(); setBusy(true); setError(''); const { data, error: insertError } = await supabase.from('challenges').insert({ ...form, creator_id: user.id, status: 'open' }).select().single(); setBusy(false); if (insertError) return setError(errorText(insertError)); navigate(`/challenge/${data.id}`) }
  return <section className="form-page"><p className="eyebrow">HOST A CHALLENGE</p><h1>Give your community a clear goal.</h1><form className="form-card" onSubmit={submit}><label>Challenge title<input required maxLength="120" value={form.title} onChange={set('title')} placeholder="e.g. Seven days of neighbourhood clean-up" /></label><label>Description<textarea required value={form.description} onChange={set('description')} placeholder="What should participants do, and what evidence makes a strong submission?" /></label><div className="two-col"><label>Category<select value={form.category} onChange={set('category')}>{categories.slice(1).map(x => <option key={x}>{x}</option>)}</select></label><label>Difficulty<select value={form.difficulty} onChange={set('difficulty')}>{difficulties.slice(1).map(x => <option key={x} value={x}>{x[0].toUpperCase() + x.slice(1)}</option>)}</select></label></div><div className="two-col"><label>Start date<input type="date" value={form.start_date} onChange={set('start_date')} /></label><label>End date<input required type="date" value={form.end_date} onChange={set('end_date')} /></label></div>{error && <p className="notice">{error}</p>}<button className="primary" disabled={busy}>{busy ? 'Creating…' : 'Publish challenge'}</button></form></section>
}

function ChallengeDetail({ user }) {
  const { id } = useParams(); const [challenge, setChallenge] = useState(null); const [participants, setParticipants] = useState([]); const [isMember, setIsMember] = useState(false); const [message, setMessage] = useState(''); const [progress, setProgress] = useState(''); const [busy, setBusy] = useState(false)
  async function load() { const [{ data: c, error }, { data: people }] = await Promise.all([supabase.from('challenges').select('*').eq('id', id).single(), supabase.from('participants').select('id, user_id, progress').eq('challenge_id', id).order('progress', { ascending: false })]); if (error) setMessage(errorText(error)); else setChallenge(c); const ids = [...new Set((people || []).map(p => p.user_id))]; const { data: profiles } = ids.length ? await supabase.from('profiles').select('id, name').in('id', ids) : { data: [] }; const names = Object.fromEntries((profiles || []).map(profile => [profile.id, profile.name])); const enriched = (people || []).map(person => ({ ...person, name: names[person.user_id] || 'Community member' })); setParticipants(enriched); setIsMember(enriched.some(p => p.user_id === user.id)) }
  useEffect(() => { load() }, [id, user.id])
  async function join() { const { error } = await supabase.from('participants').insert({ challenge_id: id, user_id: user.id }); if (error) setMessage(errorText(error)); else { setMessage('You joined the challenge.'); load() } }
  async function addProgress(event) { event.preventDefault(); setBusy(true); const { error } = await supabase.rpc('record_progress', { p_challenge_id: Number(id), p_amount: Number(progress), p_note: null, p_evidence_url: null }); setBusy(false); if (error) setMessage(errorText(error)); else { setProgress(''); setMessage('Progress recorded.'); load() } }
  if (!challenge && !message) return <p>Loading challenge…</p>
  if (!challenge) return <p className="notice">{message}</p>
  return <><section className="detail-hero"><div><div className="card-top"><span className="tag">{challenge.category}</span><span className={'difficulty ' + challenge.difficulty}>{challenge.difficulty}</span></div><h1>{challenge.title}</h1><p>{challenge.description}</p><p className="muted">Open until {formatDate(challenge.end_date)}</p></div><div className="hero-actions">{isMember ? <Link className="primary" to={`/challenge/${id}/submit`}>Submit result</Link> : <button className="primary" onClick={join}>Join challenge</button>}<Link className="secondary" to={`/leaderboard?challenge=${id}`}>Leaderboard</Link></div></section>{message && <p className="notice">{message}</p>}{isMember && <form className="progress-form" onSubmit={addProgress}><label>Add measurable progress<input required min="0.01" step="0.01" type="number" value={progress} onChange={e => setProgress(e.target.value)} placeholder="Amount" /></label><button className="secondary" disabled={busy}>{busy ? 'Saving…' : 'Record progress'}</button></form>}<section><div className="section-heading"><div><p className="eyebrow">PARTICIPANTS</p><h2>{participants.length} people taking part</h2></div></div><div className="participant-list">{participants.map(p => <div className="participant" key={p.id}><span className="avatar">{p.name[0].toUpperCase()}</span><span>{p.name}</span><div className="progress"><i style={{ width: `${Math.min(100, p.progress || 0)}%` }} /></div><strong>{p.progress || 0}%</strong></div>)}</div></section></>
}

function SubmitResult({ user }) {
  const { id } = useParams(); const navigate = useNavigate(); const [content, setContent] = useState(''); const [proofUrl, setProofUrl] = useState(''); const [message, setMessage] = useState(''); const [busy, setBusy] = useState(false)
  async function submit(event) { event.preventDefault(); setBusy(true); const { error } = await supabase.rpc('submit_submission', { p_challenge_id: Number(id), p_content: content, p_proof_url: proofUrl || null, p_payload: {} }); setBusy(false); if (error) setMessage(errorText(error)); else navigate(`/challenge/${id}`) }
  return <section className="form-page"><p className="eyebrow">SUBMIT YOUR RESULT</p><h1>Show the work behind your progress.</h1><form className="form-card" onSubmit={submit}><label>Reflection and result<textarea required value={content} onChange={e => setContent(e.target.value)} placeholder="Describe what you completed, what you learned, and how your evidence supports it." /></label><label>Proof link <span className="muted">(optional)</span><input type="url" value={proofUrl} onChange={e => setProofUrl(e.target.value)} placeholder="https://…" /></label>{message && <p className="notice">{message}</p>}<button className="primary" disabled={busy}>{busy ? 'Submitting…' : 'Submit for review'}</button></form></section>
}

function Leaderboard() {
  const [params] = useSearchParams(); const challengeId = params.get('challenge'); const [rows, setRows] = useState([]); const [names, setNames] = useState({}); const [message, setMessage] = useState(''); const [loading, setLoading] = useState(true)
  useEffect(() => { (async () => { let query = supabase.from('scores').select('final_score, completion_score, quality_score, verification_score, peer_score, calculated_at, submissions!inner(id, challenge_id, user_id, challenges(title))').eq('is_published', true).order('final_score', { ascending: false }); if (challengeId) query = query.eq('submissions.challenge_id', challengeId); const { data, error } = await query; if (error) setMessage(errorText(error)); else { setRows(data || []); const ids = [...new Set((data || []).map(r => r.submissions.user_id))]; if (ids.length) { const profiles = await supabase.from('profiles').select('id, name').in('id', ids); setNames(Object.fromEntries((profiles.data || []).map(p => [p.id, p.name]))) } } setLoading(false) })() }, [challengeId])
  return <section><p className="eyebrow">RECOGNITION</p><h1>{challengeId ? 'Challenge leaderboard' : 'Community leaderboard'}</h1><p className="muted">Scores combine completion, evidence quality, verification, and calibrated peer review.</p>{message && <p className="notice">{message}</p>}<div className="leaderboard">{loading ? <p>Loading rankings…</p> : rows.length ? rows.map((row, index) => <article className="score-row" key={row.submissions.id}><span className="rank">#{index + 1}</span><div className="score-person"><strong>{names[row.submissions.user_id] || 'Community member'}</strong><small>{row.submissions.challenges?.title}</small></div><div className="breakdown">{scoreLabels.map(([key, label]) => <span key={key}>{label} <b>{Number(row[key]).toFixed(0)}</b></span>)}</div><strong className="final-score">{Number(row.final_score).toFixed(1)}</strong></article>) : <div className="empty">No verified, published results yet.</div>}</div></section>
}

function Profile({ user }) {
  const [data, setData] = useState({ profile: null, joined: [], created: [], scores: [] }); const [message, setMessage] = useState('')
  useEffect(() => { (async () => { const [profile, joined, created, scores] = await Promise.all([supabase.from('profiles').select('*').eq('id', user.id).single(), supabase.from('participants').select('progress, challenges(*)').eq('user_id', user.id), supabase.from('challenges').select('*').eq('creator_id', user.id), supabase.from('scores').select('final_score, calculated_at, submissions!inner(challenge_id, user_id, challenges(title))').eq('submissions.user_id', user.id).order('calculated_at', { ascending: false })]); setData({ profile: profile.data, joined: joined.data || [], created: created.data || [], scores: scores.data || [] }); setMessage(profile.error || joined.error || created.error || scores.error ? 'Some profile information could not be loaded.' : '') })() }, [user.id])
  return <section><p className="eyebrow">YOUR SPACE</p><h1>{data.profile?.name || user.email}</h1><p className="muted">{user.email}</p>{message && <p className="notice">{message}</p>}<div className="profile-grid"><div className="card"><h2>Challenges joined</h2>{data.joined.length ? data.joined.map(row => <Link className="list-link" key={row.challenges.id} to={`/challenge/${row.challenges.id}`}>{row.challenges.title}<b>{row.progress || 0}%</b></Link>) : <p className="muted">No challenges joined yet.</p>}</div><div className="card"><h2>Challenges created</h2>{data.created.length ? data.created.map(c => <Link className="list-link" key={c.id} to={`/challenge/${c.id}`}>{c.title}<span>{c.status}</span></Link>) : <p className="muted">No challenges created yet.</p>}</div><div className="card"><h2>Score history</h2>{data.scores.length ? data.scores.map((s, i) => <div className="list-link" key={i}><span>{s.submissions.challenges?.title}</span><b>{Number(s.final_score).toFixed(1)}</b></div>) : <p className="muted">Published scores will appear here.</p>}</div></div></section>
}

function App() {
  const { session, loading } = useAuth(); const navigate = useNavigate()
  useEffect(() => { if (session?.user) ensureProfile(session.user).catch(console.error) }, [session?.user?.id])
  if (!isConfigured) return <div className="setup"><h1>Connect Supabase</h1><p>Copy <code>.env.example</code> to <code>.env</code> and add your project URL and anon key.</p></div>
  if (loading) return <div className="setup">Loading…</div>
  if (!session) return <Shell><Routes><Route path="*" element={<AuthPage onReady={() => navigate('/')} />} /></Routes></Shell>
  return <Shell session={session}><Routes><Route path="/" element={<Browse user={session.user} />} /><Route path="/auth" element={<Navigate to="/" replace />} /><Route path="/create" element={<CreateChallenge user={session.user} />} /><Route path="/challenge/:id" element={<ChallengeDetail user={session.user} />} /><Route path="/challenge/:id/submit" element={<SubmitResult user={session.user} />} /><Route path="/leaderboard" element={<Leaderboard />} /><Route path="/profile" element={<Profile user={session.user} />} /><Route path="*" element={<Navigate to="/" replace />} /></Routes></Shell>
}

export default App
