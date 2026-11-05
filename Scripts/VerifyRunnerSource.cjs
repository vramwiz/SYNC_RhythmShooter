// Non-build checks. Reads source + prior native fixture JSON; never runs Delphi,
// EXEs, GUI, audio playback, deployment, or writes the saved fixture plans.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
function option(name,fallback){const i=process.argv.indexOf(name);return i<0?fallback:process.argv[i+1];}
const actionPath=option('--action-source',path.join(root,'Source/Runner/RhythmRunnerAction.pas'));
const corpus=option('--fixtures',path.join(root,'Win64/NativeTests/RunnerPlanSmoke/Checked/TestUserData/SYNC_RhythmRunner/Plans'));
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const action=fs.readFileSync(actionPath,'utf8'),pixels=read('Source/Runner/RhythmRunnerPixels.pas'),legacy=read('Source/Runner/RhythmRunnerPlan.pas');
function body(name,next){const a=action.indexOf('function TRunnerActionPlan.'+name+'(');assert(a>=0,name);const b=next?action.indexOf('function TRunnerActionPlan.'+next+'(',a+1):action.indexOf('class function TRunnerActionPlan.Build(',a+1);assert(b>a,name+' end');return action.slice(a,b);}
const hero=body('HeroAt','BladeAt'),blade=body('BladeAt','EnemyBladeAt'),enemy=body('EnemyBladeAt');
function number(regex,text,label){const m=text.match(regex);assert(m,label);return Number(m[1]);}
const poseStart=number(/if Age< ([+-]?[\d.]+) then Result.Pose:=3/,hero,'pose threshold');
const bladeStart=number(/if Age< ([+-]?[\d.]+) then begin Grip:=/,blade,'blade threshold');
let timing=0;
for(const beat of [0.18,1,96,3000])for(const delta of [-0.020,-0.012,-0.006,-0.001,-0.0001,0,0.001,0.025]){
  const age=beat+delta-beat;
  const phase=age<bladeStart?'anticipation':age<=0.025?'contact':'follow';
  const pose=age<poseStart?3:age<=0.025?4:5;
  if(delta<0){assert.notEqual(phase,'contact',`blade reaches contact ${-delta*1000} ms before beat ${beat}`);assert.notEqual(pose,4,'early contact pose');}
  if(delta===0){assert.equal(phase,'contact');assert.equal(pose,4);}
  timing++;
}
assert.match(hero,/if H.Kind=rhHurt then begin if Age<0 then Result.Pose:=6 else Result.Pose:=7;/,'hurt must start at the enemy impact');
assert.match(blade,/Tip:=Pt\(H.X,H.Y\)/,'exact planned blade contact');
assert.match(blade,/Grip:=Pt\(P.X\+0.012,P.Y-0.12\);Tip:=Pt\(Grip.X-0.04,Grip.Y-0.065\)/,'retain prior anticipation pose');
assert.match(enemy,/U:=EnsureRange\(1\+Age\/0.28,0.0,1.0\)/,'enemy attack arrives on the accent');
assert.match(pixels,/if Pose=7 then begin Burst/,'damage burst follows hurt pose');
assert.match(pixels,/A:=T-H.Time;if A>0.26 then Break/,'impact age is relative to raw time');
assert.match(pixels,/if \(Age<0\) or \(Age>0.26\) then Exit/,'no pre-impact burst');
assert.match(pixels,/if T>=H.Kill then begin/,'enemy defeat starts on its kill time');
assert.match(legacy,/if FAction<>nil then begin Pose:=FAction.HeroAt\(Time\)/,'v6 PositionAt forwarding');
assert.match(read('Source/Shared/Settings/RhythmStyles.pas'), /Id:'runner'.*Versions:\[1,2,3,4,5,6,7\]/,'legacy Runner plans');
assert(!read('Source/Runner/RhythmRunnerScene.pas').includes('TRunnerPlan.Build('),'render must not build a score');
const restore=action.slice(action.indexOf('class function TRunnerActionPlan.FromJSON('));
assert(!restore.includes('.Build('),'cold restore must not re-plan');
assert.match(restore,/Result.IndexActions;Result.Validate/,'derive indexes from saved rows');
assert.match(action,/Median<=0.38/);assert.match(action,/Median>=0.52/);assert.match(action,/Time-Last>=3.0/);
assert.match(action,/Audio.BossCount-1/);assert.match(action,/Result.Pads\[High\(Result.Pads\)\].Right:=Result.WorldAt\(Result.Goal\)\+3.0/);
assert.match(action,/while \(Cursor<Length\(Result.Hits\)\) and \(Result.Hits\[Cursor\].Section=K\) do Inc\(Cursor\)/,'section range uses assigned IDs');
assert.equal((action.match(/Cursor:=/g)||[]).length,1,'range cursor must not be reused by HP bookkeeping');
assert.match(action,/I>=Sections\[K\].First\) and \(I<=Sections\[K\].Last/,'reject omitted boundary accents');
assert.match(pixels,/First\+191/);assert.match(pixels,/Drawn>=64/);assert.match(pixels,/Last-95/);assert.match(pixels,/for I:=0 to 127/);
assert.match(read('Tests/RunnerPlanSmoke.dpr'),/CheckContactTiming\(Score,I\)/,'native regression prepared');
const SPEED=number(/RA_SPEED=([\d.]+)/,action,'speed'),GROUND=number(/RA_GROUND=([\d.]+)/,action,'ground'),GRAVITY=number(/RA_GRAVITY=([\d.]+)/,action,'gravity');
function near(a,b,label,epsilon=1e-7){assert(Math.abs(a-b)<=epsilon,`${label}: ${a} / ${b}`);}
function decode(hex){assert.match(hex,/^[0-9A-F]{16}$/);const value=Buffer.from(hex,'hex').readDoubleBE();assert(Number.isFinite(value));const b=Buffer.alloc(8);b.writeDoubleBE(value);assert.equal(b.toString('hex').toUpperCase(),hex);return value;}
function before(rows,time,column=0){let a=0,b=rows.length;while(a<b){const m=(a+b)>>1;if(rows[m][column]<=time)a=m+1;else b=m;}return a-1;}
const stats={fixturePlans:0,legacyFixtureVersions:[],binary64Values:0,landings:0,departureChecks:0,movingBeforeJump:0,fallChecks:0,floorSamples:0,boundaries:0,bossSections:0,heroContacts:0,enemyContacts:0,exitSourceModelSamples:0,priorPlansWithInvalidRanges:0,priorBoundaryAccentsRecoveredInSourceModel:0};
const kinds=new Set(),mixed=[];
assert(fs.existsSync(corpus),'prior native fixture plans are unavailable; supply --fixtures');
for(const file of fs.readdirSync(corpus).filter(n=>n.endsWith('.json'))){
  const raw=fs.readFileSync(path.join(corpus,file),'utf8').replace(/^\ufeff/,'');const doc=JSON.parse(raw);
  if(doc.style==='runner' && doc.version<6){stats.legacyFixtureVersions.push(doc.version);continue;}
  if(doc.version!==6 || doc.action?.policy!=='abc-moving-pixel-v1')continue;
  const p=doc.action,sections=p.sections.map(r=>r.map(decode)),pads=p.pads.map(r=>r.map(decode)),jumps=p.jumps.map(r=>r.map(decode)),hits=p.hits.map(r=>r.map(decode));
  stats.fixturePlans++;stats.binary64Values+=[...p.sections,...p.pads,...p.jumps,...p.hits].reduce((n,r)=>n+r.length,0);
  const sectionAt=t=>Math.max(0,before(sections,t));
  const world=t=>{t=Math.max(0,Math.min(p.goal+1.6,t));const s=sections[sectionAt(Math.min(t,p.goal))];return s[2]+(s[3]===2?0:SPEED*(Math.min(t,p.goal)-s[0]))+(t>p.goal?SPEED*(t-p.goal)+1.5*Math.max(0,t-p.goal-0.25)**2:0);};
  const offset=(pad,t)=>{const z=Math.sin((t-pad[0])*2*Math.PI/pad[8]+pad[7])-Math.sin(pad[7]);return [pad[5]*z,pad[6]*z];};
  const padAt=(i,t)=>{const pad=pads[i],o=offset(pad,t);return [pad[2]+o[0],pad[3]+o[0],pad[4]+o[1]+(pad[9]>=0 && t>pad[9]?2.8*(t-pad[9])**2:0)];};
  const heroBase=t=>{const s=sections[sectionAt(t)];let x=world(t),y=GROUND;if(s[3]===0){const pad=pads[Math.max(0,before(pads,t))],o=offset(pad,t);x+=o[0];y=pad[4]+o[1];}const k=before(jumps,t,1);if(k>=0){const j=jumps[k];if(t>=j[1]&&t<j[0]){const a=t-j[1],u=a/(j[0]-j[1]);x=j[2]+(j[4]-j[2])*u;y=j[3]+j[6]*a+0.5*GRAVITY*a*a;}}return [x,y];};
  assert.equal(hits.length+p.excluded,p.sourceCount);near(sections.at(-1)[1],Math.max(0.001,p.goal),'end');
  const meaningfulA=sections.some(s=>s[3]===0&&s[1]-s[0]>=3&&jumps.some(j=>j[9]>=0&&j[0]>=s[0]&&j[0]<s[1]));
  const meaningfulB=sections.some(s=>s[3]===1&&s[1]-s[0]>=3&&hits.some(h=>h[11]===2&&h[0]>=s[0]&&h[0]<s[1]));
  if(meaningfulA&&meaningfulB)mixed.push(file);
  const omitted=hits.filter((h,i)=>i<sections[h[7]][4]||i>sections[h[7]][5]);
  if(omitted.length)stats.priorPlansWithInvalidRanges++;
  // Apply the current source's range enumeration to copies. Old malformed
  // saved plans are diagnosed above; the files themselves remain untouched.
  let cursor=0;for(let i=0;i<sections.length;i++){const s=sections[i],oldLast=s[5];s[4]=cursor;while(cursor<hits.length&&hits[cursor][7]===i)cursor++;s[5]=cursor-1;
    if(s[3]===2){const kill=hits.filter(h=>h[7]===i&&h[11]===7)[0];for(let n=oldLast+1;n<=s[5];n++){const h=hits[n];assert(h[0]>kill[0]-0.46,'recovered accent must be in the existing terminal pulse window');h[11]=0;stats.priorBoundaryAccentsRecoveredInSourceModel++;}}
  }
  for(let i=0;i<sections.length;i++){const s=sections[i];if(i){near(s[0],sections[i-1][1],'section boundary');const a=heroBase(s[0]-1e-7),b=heroBase(s[0]);assert(Math.hypot(a[0]-b[0],a[1]-b[1])<1e-5,'boundary teleport');stats.boundaries++;}
    if(s[3]===2){near(world(s[0]+0.1),world(s[1]-0.1),'boss scroll stop');const hs=hits.filter(h=>h[7]===i),kills=hs.filter(h=>h[11]===7);assert.equal(kills.length,1,'boss final impact');assert.equal(kills[0][9],0,'boss HP reaches zero');assert(hs.filter(h=>h[0]>kills[0][0]).every(h=>h[11]===0),'attack after defeat');stats.bossSections++;}
  }
  for(const j of jumps){const [time,takeoff,sx,sy,x,y,velocity,target,from]=j,land=padAt(target,time),launch=padAt(from,takeoff);near(y,land[2],'moving landing');near(sy,launch[2],'moving launch');near(sy+velocity*(time-takeoff)+0.5*GRAVITY*(time-takeoff)**2,y,'ballistic endpoint');assert(x>=land[0]&&x<=land[1]);assert(sx>=launch[0]&&sx<=launch[1]);const foot=heroBase(time);near(foot[0],x,'foot x');near(foot[1],y,'foot y');stats.landings++;stats.departureChecks++;
    if(pads[target][5]||pads[target][6]){assert(Math.hypot(...offset(pads[target],takeoff-0.18))>1e-7,'pre-jump movement');stats.movingBeforeJump++;}
    near(pads[from][9],takeoff+0.10,'fall after departure');assert(padAt(from,takeoff+0.5)[2]>pads[from][4]+0.30,'floor fall');stats.fallChecks++;
    for(let n=1;n<32;n++){const t=takeoff+(time-takeoff)*n/32,h=heroBase(t);for(let k=Math.max(0,from-1);k<=Math.min(pads.length-1,target+1);k++){const f=padAt(k,t);if(h[0]+0.009>=f[0]&&h[0]-0.009<=f[1]){assert(h[1]<=f[2]+0.001,'floor penetration');stats.floorSamples++;}}}
  }
  for(let i=0;i<hits.length;i++){const h=hits[i];assert.equal(h[6],i);assert.equal(h[7],sectionAt(h[0]));kinds.add(h[11]);if([2,3,4,7].includes(h[11]))stats.heroContacts++;if([4,5,6].includes(h[11])){const s=sections[h[7]],u=1+(h[0]-h[0])/0.28;near((s[2]+0.26)+(h[2]-s[2]-0.26)*u,h[2],'enemy tip x');stats.enemyContacts++;}}
  // Prior native fixture data predates the last Build() exit extension.
  // Exercise the source's +3 extension on a copy, never mutate the saved plan.
  const lastRight=world(p.goal)+3.0;for(let n=0;n<=160;n++){const t=p.goal+n/100,x=world(t);if(x<=world(p.goal)+1.40){assert(x<=lastRight,'visible exit floor');stats.exitSourceModelSamples++;}}
}
stats.legacyFixtureVersions=[...new Set(stats.legacyFixtureVersions)].sort();
assert(stats.fixturePlans>=16,'16 prior fixture plans required');assert.deepEqual(stats.legacyFixtureVersions,[1,2,3,4,5]);assert(mixed.length>=3);assert(stats.bossSections>0);for(let k=2;k<=7;k++)assert(kinds.has(k),'missing attack kind '+k);
const result={verification:'source guards and numeric reconstruction of prior native JSON; NOT Delphi/native execution',nativeExecuted:false,buildExecuted:false,guiExecuted:false,actionSourceSHA256:crypto.createHash('sha256').update(action).digest('hex'),timingThresholdSamples:timing,mixedABPlans:mixed.length,...stats,remaining:'Rebuild native tests and review preview/DLL in the user build environment; prior compiled EXEs do not contain this source change.'};
const output=option('--report',null);if(output)fs.writeFileSync(output,JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
