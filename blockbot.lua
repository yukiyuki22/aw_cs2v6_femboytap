local MOVE_MAX=1.0
local AXIS_HYST=1.30
local TICK_PRED=3.0
local DEADBAND=0.5
local COUNTERSTRAFE_THRESH=0.0

local HEAD_R=26.0
local HEAD_DZ=0.04
local HEAD_H1=64.0
local HEAD_H2=46.0
local HEAD_ZT=12.0
local HEAD_JVZ=30.0
local HEAD_DVZ=-30.0

local RH=24
local Y0=8

local embedded=rawget(_G,"FEMBOY_BLOCKBOT_EMBED") and true or false
local embeddedUi=rawget(_G,"FEMBOY_BLOCKBOT_UI")

local wnd=not embedded and gui.Window("bb_wnd","Blockbot",100,100,250,230) or nil

local function row(c,n) c:SetPosY(Y0+n*RH) c:SetPosX(8) return c end

local cb_on,cb_dot,cp_dot,cb_grid,cp_grid,sl_hx,sl_hy
if embedded then
    cb_on,cb_dot,cp_dot,cb_grid,cp_grid,sl_hx,sl_hy=embeddedUi.on,embeddedUi.dot,embeddedUi.dotColor,embeddedUi.grid,embeddedUi.gridColor,embeddedUi.hudX,embeddedUi.hudY
else
    cb_on=row(gui.Checkbox(wnd,"bb_on","Enable",false),0)
    cb_dot=row(gui.Checkbox(wnd,"bb_dot","Target Dot",true),1)
    cp_dot=row(gui.ColorPicker(wnd,"bb_dc","",255,80,30,255),2)
    cb_grid=row(gui.Checkbox(wnd,"bb_gr","3D Grid",true),3)
    cp_grid=row(gui.ColorPicker(wnd,"bb_gc","",0,180,255,255),4)
    sl_hx=row(gui.Slider(wnd,"bb_hx","HUD X",16,0,3840,1),5)
    sl_hy=row(gui.Slider(wnd,"bb_hy","HUD Y",900,0,2160,1),6)
end

local font=draw.CreateFont("Verdana",11,400)
local font_bold=draw.CreateFont("Verdana",11,700)
local menu=gui.Reference("MENU")

local target=nil
local mode="OFF"
local axis=nil

local function valueOf(control)
    if control.Get then return control:Get() end
    return control:GetValue()
end

local function colorOf(control)
    if control.Get then return unpack(control:Get()) end
    return control:GetValue()
end

local skip={["C_CSGO_PreviewPlayer"]=true,["CCSPlayerController"]=true,["C_CSGO_TeamPreviewPlayer"]=true}

local vc={}

local function cl(v,a,b) if v<a then return a end if v>b then return b end return v end
local function vv(v) return v and type(v.x)=="number" and type(v.y)=="number" and type(v.z)=="number" end
local function ny(y) while y>180 do y=y-360 end while y<-180 do y=y+360 end return y end
local function np(p) if p>89 then p=89 end if p<-89 then p=-89 end return p end

local function gt(e)
    local o,t=pcall(function() return e:GetPropInt("m_iTeamNum") end)
    if o and t then return t end
    o,t=pcall(function() return e:GetTeamNumber() end)
    if o and t then return t end
    return 0
end

local function gc(e)
    if not e then return "" end
    local o,v=pcall(function() return e:GetClass() end)
    if o and v and v~="" then return v end
    o,v=pcall(function() return e:GetClassname() end)
    if o and v and v~="" then return v end
    return ""
end

local function gn(e)
    if not e then return "?" end
    local o,i=pcall(function() return e:GetIndex() end)
    if o and i then
        local o2,n=pcall(function() return client.GetPlayerNameByIndex(i) end)
        if o2 and n and n~="" then return n end
    end
    return "?"
end

local function vp(e)
    if not e then return false end
    if skip[gc(e)] then return false end
    local o,a=pcall(function() return e:IsAlive() end)
    if not (o and a) then return false end
    o,p=pcall(function() return e:GetAbsOrigin() end)
    if not (o and vv(p)) then return false end
    if p.x==0 and p.y==0 and p.z==0 then return false end
    return true
end

local function rv(e)
    local o,i=pcall(function() return e:GetIndex() end)
    if not o or not i then return {x=0,y=0,z=0} end
    o,p=pcall(function() return e:GetAbsOrigin() end)
    if not o or not vv(p) then return {x=0,y=0,z=0} end
    local now=0
    local ok,tc=pcall(function() return globals.TickCount() end)
    if ok and tc then now=tc else now=common.Time()*64 end
    local c=vc[i]
    if c and (now-c.t)>0 and (now-c.t)<=32 then
        local dt=(now-c.t)/64
        vc[i]={x=p.x,y=p.y,z=p.z,t=now}
        return {x=(p.x-c.x)/dt,y=(p.y-c.y)/dt,z=(p.z-c.z)/dt}
    end
    vc[i]={x=p.x,y=p.y,z=p.z,t=now}
    return {x=0,y=0,z=0}
end

local function ea(e)
    if not e then return nil end
    local o,a=pcall(function() return e:GetEyeAngles() end)
    if o and a then
        local p=a.x or a.pitch local y=a.y or a.yaw
        if type(p)=="number" and type(y)=="number" then return {x=p,y=y,z=a.z or a.roll or 0} end
    end
    return nil
end

local function dk(e)
    if not e then return 0 end
    local o,v=pcall(function() return e:GetPropFloat("m_flDuckAmount") end)
    if o and type(v)=="number" then return cl(v,0,1) end
    o,v=pcall(function() return e:GetPropBool("m_bDucked") end)
    if o and v~=nil then return v and 1 or 0 end
    return 0
end

local function me()
    local o,p=pcall(function() return entities.GetLocalPawn() end)
    if o and p and vp(p) then return p end
    local c=entities.GetLocalPlayer()
    if c then
        if vp(c) then return c end
        local o2,h=pcall(function() return c:GetPropEntity("m_hPawn") end)
        if o2 and h and vp(h) then return h end
    end
    return nil
end

local function ca(cmd,p)
    local o,a=pcall(function() return cmd.viewangles end)
    if o and a then
        local p=a.x or a.pitch local y=a.y or a.yaw
        if type(p)=="number" and type(y)=="number" then return {x=p,y=y,z=a.z or a.roll or 0} end
    end
    o,a=pcall(function() return cmd:GetViewAngles() end)
    if o and a then
        local p=a.x or a.pitch local y=a.y or a.yaw
        if type(p)=="number" and type(y)=="number" then return {x=p,y=y,z=a.z or a.roll or 0} end
    end
    if p then local e=ea(p) if e then return e end end
    return {x=0,y=0,z=0}
end

local function cy(cmd,p) return ca(cmd,p).y or 0 end

local function sa(cmd,p,pit,yaw,rol)
    local a=ca(cmd,p)
    a.x=type(pit)=="number" and pit or a.x
    a.y=type(yaw)=="number" and yaw or a.y
    a.z=type(rol)=="number" and rol or (a.z or 0)
    pcall(function() cmd.viewangles=EulerAngles(a.x,a.y,a.z) end)
    pcall(function() cmd:SetViewAngles(EulerAngles(a.x,a.y,a.z)) end)
    pcall(function() cmd.viewangles=a end)
end

local function gb(cmd)
    local o,b=pcall(function() return cmd:GetButtons() end)
    if o and type(b)=="number" then return b end
    o,b=pcall(function() return cmd.buttons end)
    if o and type(b)=="number" then return b end
    return 0
end

local function sb(cmd,b) pcall(function() cmd:SetButtons(b) end) pcall(function() cmd.buttons=b end) end

local function Move(cmd, flXMove, flYMove, flScalar)
    flScalar = flScalar or 1.0
    if flScalar == 0 or (flXMove == 0 and flYMove == 0) then
        pcall(function() cmd:SetForwardMove(0) end)
        pcall(function() cmd:SetSideMove(0) end)
        cmd.forwardmove = 0
        cmd.sidemove = 0
        return
    end

    local o,ang = pcall(function() return (Vector3(flXMove, flYMove, 0)):Angles() end)
    if o and ang then
        local va = ca(cmd,nil)
        ang.y = ang.y - va.y
        local o2,vec = pcall(function() return ang:Forward() end)
        if o2 and vec then
            local sx = vec.x * flScalar
            local sy = vec.y * flScalar
            pcall(function() cmd:SetForwardMove(sx) end)
            pcall(function() cmd:SetSideMove(sy) end)
            cmd.forwardmove = sx
            cmd.sidemove = sy
            return
        end
    end

    local yaw = math.rad(ca(cmd,nil).y)
    local sx = flXMove * math.cos(yaw) + flYMove * math.sin(yaw)
    local sy = -flXMove * math.sin(yaw) + flYMove * math.cos(yaw)
    sx = cl(sx * flScalar, -MOVE_MAX, MOVE_MAX)
    sy = cl(sy * flScalar, -MOVE_MAX, MOVE_MAX)
    pcall(function() cmd:SetForwardMove(sx) end)
    pcall(function() cmd:SetSideMove(sy) end)
    cmd.forwardmove = sx
    cmd.sidemove = sy
end

local function jd(cmd,j,d)
    if not bit or not bit.bor then return end
    local b=gb(cmd)
    b=bit.band(b,bit.bnot(bit.bor(2,4)))
    if j then b=bit.bor(b,2) end
    if d then b=bit.bor(b,4) end
    sb(cmd,b)
end

local function chx(mp,tp,tv,cur)
    local gx=math.abs(tp.x-mp.x) local gy=math.abs(tp.y-mp.y)
    local w=(gx>gy) and "Y" or "X"
    if not cur then return w end
    if cur==w then return cur end
    if cur=="X" then return gx>gy*AXIS_HYST and "Y" or "X" end
    return gy>gx*AXIS_HYST and "X" or "Y"
end

local function hlk(cmd,pawn,mp,ent,tp,tv,mv)
    local a=ea(ent)
    if a then sa(cmd,pawn,np(a.x or 0),ny(a.y or 0),nil) end

    local gx=tp.x-mp.x local gy=tp.y-mp.y
    local mx=(mv.x or 0)*0.01 local my=(mv.y or 0)*0.01
    local tx=0 local ty=0

    if math.abs(gx)>HEAD_DZ then
        if (gx>0 and gx-mx<0) or (gx<0 and gx-mx>0) then
            tx=-gx*2.2
        else
            tx=gx*0.35
        end
    end

    if math.abs(gy)>HEAD_DZ then
        if (gy>0 and gy-my<0) or (gy<0 and gy-my>0) then
            ty=-gy*2.2
        else
            ty=gy*0.35
        end
    end

    Move(cmd, tx, ty, 1.0)
    jd(cmd,(tv.z or 0)>HEAD_JVZ,dk(ent)>0.5 or (tv.z or 0)<HEAD_DVZ)
end

local function blk(cmd,pawn,mp,tp,tv)
    axis=chx(mp,tp,tv,axis)

    local flTickInterval = 0.015625
    local o,ti=pcall(function() return globals.TickInterval() end)
    if o and ti and ti>0 then flTickInterval=ti end

    local predTX = tp.x + tv.x * flTickInterval
    local predTY = tp.y + tv.y * flTickInterval
    local predTZ = tp.z + tv.z * flTickInterval

    local lv = rv(pawn)

    local predLX = mp.x + lv.x * flTickInterval * TICK_PRED
    local predLY = mp.y + lv.y * flTickInterval * TICK_PRED

    local dX = predTX - predLX
    local dY = predTY - predLY
    local dZ = predTZ - mp.z

    local flXMove=0
    local flYMove=0

    if axis=="X" then
        if math.abs(dX)>DEADBAND then
            -- Counterstrafe if predicted local velocity will overshoot
            if (dX>0 and dX - lv.x*flTickInterval*TICK_PRED < COUNTERSTRAFE_THRESH) or (dX<0 and dX - lv.x*flTickInterval*TICK_PRED > -COUNTERSTRAFE_THRESH) then
                flXMove = -dX
            else
                flXMove = dX
            end
        end
    else
        if math.abs(dY)>DEADBAND then
            if (dY>0 and dY - lv.y*flTickInterval*TICK_PRED < COUNTERSTRAFE_THRESH) or (dY<0 and dY - lv.y*flTickInterval*TICK_PRED > -COUNTERSTRAFE_THRESH) then
                flYMove = -dY
            else
                flYMove = dY
            end
        end
    end

    local maxDelta = 64.0
    if math.abs(flXMove)>maxDelta then flXMove = flXMove / math.abs(flXMove) * maxDelta end
    if math.abs(flYMove)>maxDelta then flYMove = flYMove / math.abs(flYMove) * maxDelta end

    local scalar = 1.0 / maxDelta
    flXMove = cl(flXMove * scalar, -MOVE_MAX, MOVE_MAX)
    flYMove = cl(flYMove * scalar, -MOVE_MAX, MOVE_MAX)

    Move(cmd, flXMove, flYMove, 1.0)

    local gap = axis=="X" and math.abs(dX) or math.abs(dY)
    mode=gap>6 and "CHASE" or "SYNC"
end

local function clr() target=nil axis=nil end

local function vt()
    if not target then return false end
    if not vp(target) then clr() return false end
    return true
end

local function oh(mp,ent,tp)
    local dx=tp.x-mp.x local dy=tp.y-mp.y
    local xy=dx*dx+dy*dy
    local hz=tp.z+HEAD_H1+(HEAD_H2-HEAD_H1)*dk(ent)
    return xy<=HEAD_R*HEAD_R and math.abs(mp.z-hz)<=HEAD_ZT
end

local function col(cls,o,s)
    local ok,l=pcall(function() return entities.FindByClass(cls) end)
    if not ok or not l then return end
    for i=1,#l do
        local e=l[i] local o2,idx=pcall(function() return e:GetIndex() end)
        if o2 and idx and not s[idx] then s[idx]=true table.insert(o,e) end
    end
end

local function pwn()
    local o,s={},{}
    col("C_CSPlayerPawn",o,s) col("CCSPlayerPawn",o,s) col("CCSPlayer",o,s)
    return o
end

local function BBMove(cmd)
    if not valueOf(cb_on) then mode="OFF" clr() return end

    local m=me()
    if not m then mode="WAIT" return end
    local mp=m:GetAbsOrigin()
    if not vv(mp) then return end

    local mi=m:GetIndex() local mt=gt(m)

    if not vt() then
        local ls=pwn() local bd=math.huge local bp=nil
        for i=1,#ls do
            local p=ls[i] local o2,pi=pcall(function() return p:GetIndex() end)
            if o2 and pi and pi~=mi and vp(p) then
                local pt=gt(p)
                if mt==0 or pt==0 or mt==pt then
                    local pos=p:GetAbsOrigin()
                    if vv(pos) then
                        local d=(pos.x-mp.x)^2+(pos.y-mp.y)^2+(pos.z-mp.z)^2
                        if d<bd then bd=d bp=p end
                    end
                end
            end
        end
        if bp then target=bp axis=chx(mp,bp:GetAbsOrigin(),rv(bp),nil) else mode="SEARCH" end
        return
    end

    local tp=target:GetAbsOrigin()
    if not vv(tp) then return end

    local tv=rv(target)

    if oh(mp,target,tp) then
        mode=dk(target)>0.5 and "HEAD-DUCK" or "HEAD"
        hlk(cmd,m,mp,target,tp,tv,rv(m))
        return
    end

    blk(cmd,m,mp,tp,tv)
end

local function BBDraw()
    if menu then
        local o,a=pcall(function() return menu:IsActive() end)
        if wnd then wnd:SetInvisible(not (o and a)) end
    end

    local m=me()
    if not m then return end

    local px=valueOf(sl_hx) local py=valueOf(sl_hy)

    local cr,cg,cb
    if not valueOf(cb_on) then
        cr,cg,cb=120,120,125
    elseif vt() then
        if mode=="SYNC" then cr,cg,cb=0,230,120
        elseif mode=="CHASE" then cr,cg,cb=255,100,80
        elseif mode=="HEAD" or mode=="HEAD-DUCK" then cr,cg,cb=80,180,255
        else cr,cg,cb=255,200,60 end
    else
        cr,cg,cb=255,160,40
    end

    local lb=mode
    local nm=vt() and gn(target) or ""
    local ax=axis or "-"

    local line1=lb
    local line2=nm~="" and ax.."  "..nm or ax

    draw.SetFont(font_bold)
    local w1,_=draw.GetTextSize(line1)
    draw.SetFont(font)
    local w2,_=draw.GetTextSize(line2)
    local tw=math.max(w1,w2)
    local th=11+4+11

    local pad_x=10
    local pad_y=6
    local total_w=tw+pad_x*2+14
    local total_h=th+pad_y*2

    draw.Color(8,8,10,175)
    draw.FilledRect(px,py,px+total_w,py+total_h)

    draw.Color(cr,cg,cb,200)
    draw.FilledRect(px,py,px+total_w,py+2)

    local dot_x=px+pad_x+2
    local dot_y=py+pad_y+5
    draw.Color(cr,cg,cb,255)
    draw.FilledRect(dot_x,dot_y,dot_x+4,dot_y+4)

    draw.SetFont(font_bold)
    draw.Color(cr,cg,cb,255)
    draw.Text(dot_x+10,dot_y-1,line1)

    draw.SetFont(font)
    draw.Color(155,155,165,255)
    draw.Text(dot_x+10,dot_y+13,line2)

    if not vt() then return end
    local o2,tp=pcall(function() return target:GetAbsOrigin() end)
    if not o2 or not vv(tp) then return end

    if valueOf(cb_dot) then
        local dr,dg,db,da=colorOf(cp_dot)
        local sx,sy=client.WorldToScreen(Vector3(tp.x,tp.y,tp.z+73))
        if sx and sy then
            draw.Color(dr,dg,db,math.floor(da*0.15))
            draw.FilledCircle(sx,sy,12)
            draw.Color(dr,dg,db,math.floor(da*0.45))
            draw.FilledCircle(sx,sy,7)
            draw.Color(dr,dg,db,da)
            draw.FilledCircle(sx,sy,4)
            draw.Color(255,255,255,200)
            draw.FilledCircle(sx,sy,1)
        end
    end

    if valueOf(cb_grid) then
        local gr,gg,gb,ga=colorOf(cp_grid)
        local h=56 local dv=7 local st=h/dv local gz=tp.z+2
        local function ln(ax,ay,bx,by,a)
            local x1,y1=client.WorldToScreen(Vector3(ax,ay,gz))
            local x2,y2=client.WorldToScreen(Vector3(bx,by,gz))
            if x1 and y1 and x2 and y2 then draw.Color(gr,gg,gb,math.floor(ga*a)) draw.Line(x1,y1,x2,y2) end
        end
        for i=-dv,dv do
            local o=i*st local f=1-math.abs(o)/h
            local a=i==0 and 0.8 or f*0.35+0.05
            ln(tp.x-h,tp.y+o,tp.x+h,tp.y+o,a)
            ln(tp.x+o,tp.y-h,tp.x+o,tp.y+h,a)
        end
    end
end

local function BBUnload()
    if embedded then
        callbacks.Unregister("PreMove","FemboyTap_BlockBot_PreMove")
        callbacks.Unregister("CreateMove","FemboyTap_BlockBot_CreateMove")
        callbacks.Unregister("Draw","FemboyTap_BlockBot_Draw")
    else
        callbacks.Unregister("PreMove","BB_PM")
        callbacks.Unregister("CreateMove","BB_CM")
        callbacks.Unregister("Draw","BB_DR")
    end
end

if embedded then
    return { Move=BBMove, Draw=BBDraw, Unload=BBUnload }
end

callbacks.Register("PreMove","BB_PM",BBMove)
callbacks.Register("CreateMove","BB_CM",BBMove)
callbacks.Register("Draw","BB_DR",BBDraw)
callbacks.Register("Unload","BB_UN",BBUnload)