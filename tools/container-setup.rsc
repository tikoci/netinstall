

:global diskprefix "disk1"
:global bridgeport "ether5"


# Create `/interface/veth` interface and IP:

    /interface veth add address=172.17.9.200/24 gateway=172.17.9.1 name=veth-netinstall
    /ip address add address=172.17.9.1/24 interface=veth-netinstall

# Create a separate bridge for `netinstall` use and add VETH to it:

    /interface bridge add name=bridge-netinstall
    /interface bridge port add bridge=bridge-netinstall interface=veth-netinstall

# Add veth and physical port, _e.g._ "ether5", to the newly created bridge: 

    /interface bridge port [find interface=$bridgeport] bridge=bridge-netinstall interface=$bridgeport

    # **OR** if not part of bridge, add port to netinstall bridge
    #        /interface bridge port add bridge=bridge-netinstall interface=$bridgeport


# Adjust the firewall so the container can download packages/netinstall binary from Mikrotik.  The exact changes needed can be specific.  But if using the default firewall, the easiest may be:

    /interface/list/member add list=LAN interface=bridge-netinstall 
    
    # **TIP** 
    # Alternatively, you can /ip/firewall/filter or NAT rules on the containers subnet, to specifically allow VETH access to the internet.  Traffic between `netinstall` is forwarded, not routed, so only needed for outbound access from the container's IP.  **How?** - depends...   

# Create some environment variables to control `netinstall` operation – adjusting all `value=` as needed:

    /container envs add key=ARCH name=NETINSTALL value=arm64
    /container envs add key=CHANNEL name=NETINSTALL value="testing"
    /container envs add key=PKGS name=NETINSTALL value="wifi-qcom"
    /container envs add key=OPTS name=NETINSTALL value="-b -r" comment=" use EITHER -r to reset to defaults or -e for an empty config; use -b to remove any branding"
   
# The `registry-url` is used to fetch "pull" images. 
    
    /container config print
    /container config set registry-url=https://registry-1.docker.io tmpdir="$diskprefix/pulls"
    
    # **NOTE** 
    # Ensure $diskprefix is a valid disk and has at least ~150MB available. 

# Create the container.  This assumes DockerHub is used:
        
    /container add remote-image=ammo74/netinstall:latest envlist=NETINSTALL interface=veth-netinstall logging=yes workdir=/app root-dir=$diskprefix/root-netinstall

# Wait for download and extract - this may take a minute or so

    # **OPTIONAL** this will loop forever to monitor, hit "Q" to stop monitoring when "started"
    /container/print interval=1s proplist=tag,status where $tag~"netinstall" or [:if ($status="stopped") do={start $".id"}]  

# Now start container, if it did not already:  
    
    /container/start [find tag~"netinstall"]   

# Issues?  Check logs...

   /log print proplist=time,message where topics~"container"



