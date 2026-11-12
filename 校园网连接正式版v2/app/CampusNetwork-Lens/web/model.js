export function connectionView(model={},connected=false,now=Date.now()){
  const expires=Date.parse(model.ExpiresAt||''),observed=Date.parse(model.ObservedAt||'');
  const fresh=connected&&['monitor','probe'].includes(model.Source)&&Number.isFinite(expires)&&expires>now&&Number.isFinite(observed)&&observed<=now+5000;
  const auth=fresh&&['Online','Offline'].includes(model.AuthState)?model.AuthState:'Unknown';
  const monitor=connected?(model.MonitorRunning?'运行中':'未开启'):'未确认';
  let tone=auth==='Online'?'online':auth==='Offline'?'offline':'unknown';
  let title=auth==='Online'?'校园网已连接':auth==='Offline'?'校园网尚未登录':'尚未确认认证状态';
  let detail=String(model.DetailText||'点击“立即检查”获取最新认证状态。');
  if(!connected){title='后台暂未连接';detail='正在尝试读取后台状态，可稍后刷新。';}
  else if(['Starting','LoggingIn','RetryWaiting','Recovering','Error'].includes(model.MonitorState)&&model.MonitorRunning){
    tone='connecting';
    title={Starting:'正在检查网络',LoggingIn:'正在登录校园网',RetryWaiting:'等待自动重试',Recovering:'正在自动恢复连接',Error:'连接需要处理'}[model.MonitorState];
    if(model.MonitorState==='RetryWaiting'){
      const nextAttempt=Date.parse(model.NextAttemptUtc||'');
      if(Number.isFinite(nextAttempt)){const seconds=Math.max(0,Math.ceil((nextAttempt-now)/1000));title=seconds>0?`${seconds} 秒后自动重试`:'即将自动重试';}
      detail=`监测会自动重试，无需反复点击检查。${model.DetailText?` ${model.DetailText}`:''}`;
    }else if(model.MonitorState==='Recovering'){
      const recoveryUntil=Date.parse(model.RecoveryUntilUtc||''),seconds=Number.isFinite(recoveryUntil)?Math.max(0,Math.ceil((recoveryUntil-now)/1000)):0;
      detail=seconds>0?`正在自动复查连接，恢复观察还剩 ${seconds} 秒；无需反复点击检查。`:'正在自动复查连接，等待最新认证结果，无需反复点击检查。';
    }
  }
  else if(!fresh){detail=model.MonitorRunning?'正在等待后台的最新检查结果。':'自动监测未开启，可点击“立即检查”只读确认连接。';}
  return {auth,monitor,tone,title,detail,fresh};
}

export function diagnosticView(result,connected,now=Date.now()){
  const presentation=result?.Presentation||{},completed=Date.parse(result?.CompletedAt||'');
  const historical=!connected||!Number.isFinite(completed)||completed>now+5000||now-completed>=30000;
  const when=Number.isFinite(completed)?new Date(completed).toLocaleString('zh-CN',{hour12:false}):'时间未确认';
  return {historical,title:historical?'上次诊断结果（需重新检查）':presentation.Title||'诊断已完成',summary:`完成于 ${when}。${historical?'此记录仅表示当时的检查结果。':presentation.Summary||''}`,advice:historical?'上次诊断不能确认当前连接，请重新运行检查。':presentation.Advice||'',completionColor:!historical&&presentation.Tone==='Success'?'green':'gold',items:(presentation.Items||[]).map(item=>historical?{...item,Tone:'Neutral',Value:`上次：${item.Value}`} :item)};
}
