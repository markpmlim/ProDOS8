_ReadTimeHex       MAC             
            Tool   $D03            
            <<<    
_Int2Hex    MAC    
            Tool   $220B           
            <<<    
_TLTextMountVol    MAC             
            Tool   $1201           
            <<<    
_MessageCenter     MAC             
            Tool   $1501           
            <<<    
_MMStartUp  MAC    
            Tool   $202            
            <<<    
_MMShutDown MAC    
            Tool   $302            
            <<<    
_NewHandle  MAC    
            Tool   $902            
            <<<    
_DisposeHandle     MAC             
            Tool   $1002           
            <<<    
PushLong    MAC    
            IF     #=]1            
            PushWord               #^]1 
            ELSE   
            PushWord               ]1+2 
            FIN    
            PushWord               ]1 
            <<<    
PushWord    MAC    
            IF     #=]1            
            PEA    ]1              
            ELSE   
            IF     MX/2            
            LDA    ]1+1            
            PHA    
            FIN    
            LDA    ]1              
            PHA    
            FIN    
            <<<    
_PtrToHand  MAC    
            Tool   $2802           
            <<<    
Tool        MAC    
            LDX    #]1             
            JSL    $E10000         
            <<<    