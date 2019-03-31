package main;

use strict;
use warnings;
use POSIX;

sub
checkPVG_Initialize($)
{
	my ($hash) = @_;
	# ....
    $hash->{DefFn}    = "checkPVG_Define";
	#$hash->{NotifyFn} = "checkPVG_Notify";
}

# ---------------------------------------------------------------------------------- #
# Erzeugt das notify, für checkMessages                                              #
# ---------------------------------------------------------------------------------- #

sub checkPVG_Define($$)
{
	my ($hash, $def) = @_;
	my $i = 0;
	my $n = 0;
	my @arraydevice = '';
	my @a = split("[ \t][ \t]*", $def);

	# Wenn ein TelegramBot Device angegeben wurde
	if (@a == 3)
	{ 	# Prüfe, ob das Device vorhanden ist
		if (Value($a[3]) ne "")
		{	
			my @device = devspec2array("TYPE=TelegramBot");
			foreach my $dev (@device)
			{	
				$dev = $_;
				if ($dev == $a[3])
				{	$arraydevice[0] = $a[3];
					$i = 1;
				}
			}
			if ($i == 0)
			{	Log 3, "checkPVG - Fehlermeldung, dass angegebene TelegramBot-Device ist kein TelegramBot Device siehe (list TYPE=TelegramBot)";
				return;
			}
		}
		else
		{	Log 3, "checkPVG - Fehlermeldung, dass angegebene TelegramBot-Device konnte nicht gefunden werden.";
			return;
		}
	}
	# Wenn zu viele Parameter angegeben wurden
	elsif (@a > 3)
	{	return "Usage: define <name> checkPVG [OPTIONAL: your-TelegramBot-Devicename]";
	}
	# Wenn kein Parameter angegeben wurde
	elsif (@a == 2)
	{	# Schreibt alle Devices ins Array, die als TYPE = TelegramBot haben
		@arraydevice = devspec2array("TYPE=TelegramBot");

		# Anzahl der Elemente im Array
		$n = scalar(@arraydevice);
	}
	# Wenn mehr als 1 Element im Array ist, sind mehrere TelegramBot Devices vorhanden -> Ermittlung des Namens kann nicht erfolgen -> Fehlermeldung
	if ($n > 1)
	{	Log 3, "checkPVG - Fehlermeldung, es wurden mehr als ein TelegramBot Device gefunden, bitte definiere das richtige manuell!";
		return;
	}
	elsif ($n == 1)
	{	
		if (Value("getMessageTelegram") eq "")
		{	fhem("defmod getMessageTelegram notify " .$arraydevice[0] .":msgId:.* { checkPVG_checkMessage(\"$arraydevice[0]\") }"); 
			fhem("attr getMessageTelegram room Telegram"); 
			Log 1, "checkPVG - Informationsmeldung, dass notify getMessageTelegram wurde erfolgreich angelegt.";	
		}
		return;
	}
	elsif ($n == 0)
	{	Log 3, "checkPVG - Fehlermeldung, es wurde kein TelegramBot Device gefunden, bitte lege laut Wiki zuerst ein TelegramBot an!";	
		return;
	}
}

# ---------------------------------------------------------------------------------- #
# Prüft eingehende Nachrichten die an den TelegramBot geschickt werden               #
# ---------------------------------------------------------------------------------- #

sub checkPVG_checkMessage($)
{
	my ($dev) 	= @_;
	my $id 		= ReadingsVal("$dev","msgPeerId","");
	my $alias 	= ReadingsVal("$dev","msgPeer","");
	my $message = ReadingsVal("$dev","msgText","");
	
    	if (($message =~ /Preisvergleich/ 
		or  $message =~ /(?i)pvg(?-i)/)
		and $message !~ /Stop/ 
		and $message !~ /Start/ 
		and $message !~ /Lösche/ 
		and $message !~ /Ändern/ 
		and $message !~ /Aktueller/ 
		and $message !~ /Hilfe/
		and $message !~ /Meine Preisvergleiche/
		and ($message !~ /Meine/ or $message !~ /(?i)pvg(?-i)/))
		{	checkPVG($dev,$message,$id); }        
        
		elsif ($message =~ /Stop/ 	
			or $message =~ /Start/ 
			or $message =~ /Lösche/ 
			or $message =~ /Ändern/ 
			or $message =~ /Aktueller/ 
			or ($message =~ /Meine/ and $message =~ /(?i)pvg(?-i)/)
			or $message =~ /Meine Preisvergleiche/)
        {   stopPVG($dev,$message,$id); }       
		elsif ($message =~ /Hilfe/g)
		{	getHelp($dev,$id); }
}

# ------------------------------------------------------------------------ #
# Preisvergleich                                                           #
# ------------------------------------------------------------------------ #
sub checkPVG($$$)
{
    my ($dev,$message,$id) = @_;
    my $link   = '';
    my $preis  = 0;
    my @array  = '';
    my $space1 = '';
    my $random = 0;
    my $i      = 0;
    my $space  = index($message,' ');
	
	if ($space != -1)
    {	for (my $i = 0; $i < 10; $i++)
        {	$space = index($message,' ');
            if ($space != -1)
            {	@array[$i] = substr($message,0,$space);
                $message = substr($message,$space+1);
                $message =~ s/^\s+//;
            }
            else
            {	@array[$i] = substr($message,0);
                last;
            }
        }
        foreach(@array)
        {	if ($_ =~ /http/g)
            { $link = $_; }
            elsif ($_ ne /http/g and ($_ ne /Preisvergleich/g or $_ ne /(?i)pvg(?-i)/))
            {	$preis = $_;
                $preis =~ s/,/./g;
                $preis =~ s/[EUROeuro€]//g;		
                $space  = index($preis,',');
                $space1 = index($preis,'.');
                if ($space == -1 and $space1 == -1)
                { $preis = $preis .'.00'; }
            }
        }        
        if ($link eq ' ')
        {   fhem "set $dev message \@$id Fehlermeldung - Es konnte keine URL ermittelt werden!";
            return;
        }
        $random = int(rand(100));
        if (Value("pvg_Artikelname$random") eq "")
        {   fhem "define pvg_Artikelname_$random HTTPMOD $link 5 ;
                  attr pvg_Artikelname_$random reading01Name Name ;
                  attr pvg_Artikelname_$random reading01Regex \"product_names\":\\\[\\\"(.*)\\\"\\\],\"product_category_ids\": ;
                  attr pvg_Artikelname_$random reading01RegOpt g ;
                  attr pvg_Artikelname_$random room Preisvergleich ;
                  setreading pvg_Artikelname_$random Link $link ;
                  setreading pvg_Artikelname_$random ID $id";
            fhem "defmod t_pvg_Artikelname_$random at +00:00:15 { getPVG(\"pvg_Artikelname_$random\",\"$dev\") } ";
      
            if ($preis > 0)
            { fhem "setreading pvg_Artikelname_$random Preiswecker $preis"; }
        }
        else
        {    fhem "set $dev message \@$id Der Preisvergleich konnte nicht angelegt werden!";
        }
    }
    else
    {	fhem "set $dev message \@$id Fehlermeldung - Bitte gib Preisvergleich + Link ein!";
    }
}

# ------------------------------------------------------------------------ #
# Preisvergleich                                                           #
# ------------------------------------------------------------------------ #

sub getPVG($$)
{
    my ($dev,$dev1) = @_;
    my $link        = ReadingsVal("$dev","Link","");
    my $id          = ReadingsVal("$dev","ID","");
    my $name        = ReadingsVal("$dev","Name","");
    my $name1       = ReadingsVal("$dev","Name","");
    my $name2       = '';
    my @arraydevice = devspec2array("TYPE=TelegramBot");
    my $preis       = ReadingsVal("$dev","Preiswecker","");    
    my $i           = 0;
    
    $name =~ s/ /_/g;
    $name =~ s/'/_/g;
    $name =~ s/%/_/g;
    $name =~ s/,/_/g;
    $name =~ s/-/_/g;
	$name =~ s/\+/Plus/g;
	$name =~ s/\(/_/g;
	$name =~ s/\)/_/g;
    $name =~ s/ä/ae/g;   
    $name =~ s/Ä/Ae/g;   
	$name =~ s/ö/oe/g;   
    $name =~ s/Ö/Oe/g;   
    $name =~ s/ü/ue/g;   
    $name =~ s/Ü/Ue/g;   
    $name =~ s/ß/ss/g;   
    
    # Anzahl der Elemente im Array
    $i = scalar(@arraydevice);

    # Wenn mehr als 1 Element im Array ist, sind mehrere TelegramBot Devices vorhanden -> Ermittlung des Namens kann nicht erfolgen -> Fehlermeldung
    if ($i > 1)
    {    fhem "set $dev1 message \@$id Fehlermeldung:\nEs wurde mehr als ein TelegramBot Device gefunden, bitte passe die Source händisch an!"; 
    }
    elsif ($i == 1)    
    {	$name2 = ReadingsVal("$arraydevice[0]","msgPeer","");
        if (Value("pvg_$name") eq "")
        {	$name = $name .'_' .$preis .'_' .$name2;
            fhem "rename $dev pvg_$name ;
                  modify pvg_$name $link 600 ;
                  attr pvg_$name event-on-change-reading Preis ;
                  attr pvg_$name reading02Name Preis ;
                  attr pvg_$name reading02Regex \"lowPrice\":(.*),\"priceCurrency\":\"EUR\" ;
                  attr pvg_$name reading02RegOpt g ;
                  attr pvg_$name reading02DeleteIfUnmatched 1 ";
            if ($preis == 0)
            {	fhem "define n_pvg_$name notify pvg_$name:.* \{ if (\$EVTPART1 > 0) \{ fhem \\\"set $dev1 message \\\@$id für $name1 ist zur Zeit \$EVTPART1 EUR!\" \} \} ; attr n_pvg_$name room Preisvergleich ; setreading n_pvg_$name Preiswecker $preis"; 
                fhem "set $dev1 message \@$id Der Preisvergleich:\n$name1\nwurde erfolgreich ohne Preisangabe angelegt.";
            }
            elsif ($preis > 0)
            {	fhem "define n_pvg_$name notify pvg_$name:.* \{ if (\$EVTPART1 < $preis and \$EVTPART1 > 0) \{ fhem \"set $dev1 message \\\@$id Dein Preiswecker für $name1 ($preis EUR) hat angeschlagen!\\nDer aktuelle Bestpreis liegt zur Zeit bei \$EVTPART1 EUR! \\nHier ist der Link zum Preisvergleich:\\n$link\" \} \} ; attr n_pvg_$name room Preisvergleich ; setreading n_pvg_$name Preiswecker $preis"; 
                fhem "set $dev1 message \@$id Dein Preiswecker ($preis EUR) für:\n$name1\nwurde erfolgreich gestartet.";
            }
        }
        else
        {	fhem "delete $dev";
            fhem "set $dev1 message \@$id Der Preisvergleich konnte nicht angelegt werden, weil ein aehnlicher Preisvergleich schon vorhanden ist!";
        }
    }
}

# ------------------------------------------------------------------------ #
# Preisvergleich STARTEN / STOPPEN                                         #
# ------------------------------------------------------------------------ #
sub stopPVG($$$)
{
    my ($dev,$message,$id) = @_;
    my $stop          = 0;
    my $start         = 0;
    my $loesche       = 0;
    my $aendern       = 0;
	my $aktueller     = 0;
    my $meine         = 0;
    my $pvg           = 0;
    my $preis         = 0;
	my $oldpreis      = 0;
    my $getpreis      = 0;
    my $name          = '';
    my $name1         = '';	
    my @array         = '';
    my @arraydevice   = devspec2array("TYPE=TelegramBot");
    my $i             = 0;
    my $n             = 0;    
    my $z             = 0;   	
    my $text          = '';
    my $dev1          = '';	
    my $def           = '';
    my $user          = '';
    my $link          = '';	
	my $save_message  = '';
	my $save_message1 = '';	
	my $space         = 0;
    
    $space  = index($message,'Preisvergleich');
    if ($space != -1)
    { $pvg = 1; }
    $space  = index($message,'Preisvergleiche');
    if ($space != -1)
    { $pvg = 1; }
    if ($message =~ /(?i)pvg(?-i)/)
	{ $pvg = 1; }
	$space  = index($message,'Stop');
    if ($space != -1)
    { $stop = 1; }
    $space  = index($message,'Start');
    if ($space != -1)
    { $start = 1; }
    $space  = index($message,'Lösche');
    if ($space != -1)
    { $loesche = 1; }
    $space  = index($message,'Ändern');
    if ($space != -1)
    { $aendern = 1; }
    $space  = index($message,'Meine');
    if ($space != -1)
    { $meine = 1; }  
    $space  = index($message,'Aktueller');
    if ($space != -1)
    { $aktueller = 1; }  	
    $space = index($message,'€');
    if ($space != -1)
    { $getpreis = 1; }       
    $space = index($message,'EUR');
    if ($space != -1)
    { $getpreis = 1; }
    $space = index($message,'EURO');
    if ($space != -1)
    { $getpreis = 1; }       
    $space = index($message,'Euro');
    if ($space != -1)
    { $getpreis = 1; }
	if ($message =~ /\d+$/)
	{ $getpreis = 1; }
    
    # Anzahl der Elemente im Array
    $n = scalar(@arraydevice);
    # Wenn mehr als 1 Element im Array ist, sind mehrere TelegramBot Devices vorhanden -> Ermittlung des Namens kann nicht erfolgen -> Fehlermeldung
    if ($n > 1)
    {   fhem "set $dev message \@$id Fehlermeldung:\nEs wurde mehr als ein TelegramBot Device gefunden, bitte passe die Source händisch an!"; 
    }
    elsif ($n == 1)    
    {   $user = ReadingsVal("$arraydevice[0]","msgPeer","");
        $message =~ s/Stop//g;
        $message =~ s/Start//g;
        $message =~ s/Lösche//g;
        $message =~ s/Ändern//g;
		$message =~ s/Aktueller//g;
        $message =~ s/Meine//g;
        $message =~ s/Preisvergleiche|Preisvergleich//g;
		$message =~ s/(?i)pvg(?-i)//g;
        $message =~ s/^\s+|\s+$//g;
        $message =~ s/ /_/g;
        
		# Log 1, "checkPVG - Informationsmeldung: Message = $message, Meine = $meine, PVG = $pvg, Ändern = $aendern";
		
        # Wenn kein PVG-Name angegeben wurde
        if ($message eq "" and $pvg == 1)
        {	foreach my $dev (devspec2array("room=Preisvergleich"))
            {	if ($dev =~ /$user/g)
                {	# Wenn das Device aktiv ist
                    if (AttrVal("$dev","disable",0) == 0 and $stop == 1)
                    {	# Nur HTTPMOD Devices raussuchen
                        if (InternalVal("$dev","TYPE","") eq "HTTPMOD")
                        {   @array[$i] = (ReadingsVal("$dev","Name",""));
                            $i = $i+1;
                        }
                    }
                    elsif (AttrVal("$dev","disable",0) == 1 and $start == 1)
                    {	# Nur HTTPMOD Devices raussuchen
                        if (InternalVal("$dev","TYPE","") eq "HTTPMOD")
                        {   @array[$i] = (ReadingsVal("$dev","Name",""));
                            $i = $i+1;
                        }
                    }                
                    elsif ($loesche == 1 or $aendern == 1 or $meine == 1 or $aktueller == 1)
                    {	# Nur HTTPMOD Devices raussuchen
                        if (InternalVal("$dev","TYPE","") eq "HTTPMOD")
                        {   @array[$i] = (ReadingsVal("$dev","Name",""));
                            $i = $i+1;
                        }
                    }                                   
                }
            }
            foreach(@array)
            {	if ($text eq "")
                {	$text = $_; }
                else
                {	$text = $text .'\n' .$_; }            
            }    
            if ($stop == 1 and $i > 0)
            {	fhem "set $dev message \@$id Du hast folgende aktive Preisvergleiche:\n$text"; }
            elsif ($start == 1 and $i > 0)
            {	fhem "set $dev message \@$id Du hast folgende inaktive Preisvergleiche:\n$text"; }        
            elsif ($stop == 1 and $i == 0)
            {	fhem "set $dev message \@$id Du hast keine aktive Preisvergleiche!"; }        
            elsif ($start == 1 and $i == 0)
            {   fhem "set $dev message \@$id Du hast keine inaktiven Preisvergleiche!"; }                
            elsif ($loesche == 1 and $i == 0)
            {   fhem "set $dev message \@$id Du hast keine Preisvergleiche, die du löschen könntest!"; }                
            elsif ($loesche == 1 and $i > 0)
            {   fhem "set $dev message \@$id Folgende Preisvergleiche kannst du löschen:\n$text"; }                 
            elsif ($aendern == 1 and $i == 0)
            {   fhem "set $dev message \@$id Du hast keine Preisvergleiche, die du ändern könntest!"; }                
            elsif ($aendern == 1 and $i > 0)
            {   fhem "set $dev message \@$id Folgende Preisvergleiche kannst du ändern:\n$text"; }                 
            elsif (($meine == 1 or $aktueller == 1) and $i == 0)
            {   fhem "set $dev message \@$id Du hast keine Preisvergleiche, leg doch am besten direkt einen Preiswecker an!"; }                
            elsif (($meine == 1  or $aktueller == 1) and $i > 0)
            {   fhem "set $dev message \@$id Folgende Preisvergleiche hast du angelegt:\n$text"; }                    
        }
        # Wenn ein PVG-Name gefunden wurde
        elsif ($message ne "" and $pvg == 1 and $aendern == 0)
        {	foreach $dev1 (devspec2array("room=Preisvergleich"))
            {	if ($dev1 =~ /$message/g)
                {	if ($dev1 =~ /$user/g)
                    {	# Wenn das Device aktiv ist
                        if (AttrVal("$dev1","disable",0) == 0 and $stop == 1)
                        {	fhem "attr $dev1 disable 1";
                            if (InternalVal("$dev1","TYPE","") eq "HTTPMOD")
                            {   my $name = (ReadingsVal("$dev1","Name",""));
                                fhem "set $dev message \@$id Du hast $name deaktiviert!";
                            }
                        }
                        elsif (AttrVal("$dev1","disable",0) == 1 and $start == 1)
                        {   fhem "attr $dev1 disable 0";
                            if (InternalVal("$dev1","TYPE","") eq "HTTPMOD")
                            {   my $name = (ReadingsVal("$dev1","Name",""));
                                fhem "set $dev message \@$id Du hast $name aktiviert!";
                            }
                        }
                        elsif ($loesche == 1)
                        {   if (InternalVal("$dev1","TYPE","") eq "HTTPMOD")
                            {   my $name = (ReadingsVal("$dev1","Name",""));
								fhem "set $dev message \@$id Du hast $name erfolgreich gelöscht!";
                            }
                            fhem "delete $dev1";
                        }
						elsif ($aktueller == 1)
						{	if (InternalVal("$dev1","TYPE","") eq "HTTPMOD")
                            {   my $name = (ReadingsVal("$dev1","Name",""));
								$preis = (ReadingsVal("$dev1","Preis",""));
								$link  = (ReadingsVal("$dev1","Link",""));
								fhem "set $dev message \@$id Der zur Zeit beste Preis für:\n" .$name ."\nbeträgt: " .$preis ."Link:\n" .$link;
                            }
						}
                    }
                }
            }
        }
		elsif ($message ne "" and $pvg == 1 and $aendern == 1)
		{	if ($getpreis > 0)
			{	foreach $dev (devspec2array("room=Preisvergleich"))
				{	if (InternalVal("$dev","TYPE","") eq "notify")
					{   my $name  = (InternalVal("$dev","NOTIFYDEV",""));
						$save_message = $message;
						$name1 = ReadingsVal("$name","Name","");
						$link  = ReadingsVal("$name","Link","");
						for (my $i = 0; $i < 10; $i++)
						{	$space = index($message,'_');
							if ($space != -1)
							{	@array[$i] = substr($message,0,$space);
								$message = substr($message,$space+1);
								$message =~ s/^\s+//;
							}
							else
							{	@array[$i] = substr($message,0);
								last;
							}
							}
							
						foreach(@array)
						{	if ($_ =~ /€/g or $_ =~ /EURO/g or $_ =~ /EUR/g or $_ =~ /\d+$/)
							{	$preis = $_;
								$save_message =~ s/$preis//g;
								if ($z == 0)
								{	$save_message1 = $save_message;
									$z = $z +1;
								}
								$preis =~ s/,/./g;
								$preis =~ s/[EUROeuro€]//g;
								$space  = index($preis,',');
								my $space1 = index($preis,'.');
								if ($space == -1 and $space1 == -1)
								{ $preis = $preis .'.00'; }
							}
						}
					}
				}
				#fhem "set $dev message \@$id SaveMessage1: $save_message1";
				foreach $dev1 (devspec2array("room=Preisvergleich"))
				{	if ($dev1 =~ /$user/g)
					{	if ($dev1 =~ /$save_message1/)
						{	if (InternalVal($dev1,"TYPE","") eq "HTTPMOD")
							{	$oldpreis   = ReadingsNum($dev1,"Preiswecker",0);
								my $oldname = $dev1;
								my $newname = $dev1;
								if ($oldpreis == 0)
								{	my $space = index($newname,'__');
									$newname = substr($newname,0,$space) .'_' .$preis .'_' .substr($newname,$space+2); }
								else
								{	$newname =~ s/$oldpreis/$preis/g; }
								$name1 = ReadingsVal("$oldname","Name","");
								fhem "rename $oldname $newname";
								fhem "setreading $newname Preiswecker $preis";
								fhem "delete n_$oldname";
								fhem "define n_$newname notify $newname:.* \{ if (\$EVTPART1 < $preis and \$EVTPART1 > 0) \{ fhem \"set $dev message \\\@$id Dein Preiswecker für $name1 ($preis EUR) hat angeschlagen!\\nDer aktuelle Bestpreis liegt zur Zeit bei \$EVTPART1 EUR! \\nHier ist der Link zum Preisvergleich:\\n$link\" \} \} ; attr n_$newname room Preisvergleich ; setreading n_$newname Preiswecker $preis"; 
								fhem "set $dev message \@$id Dein Preiswecker für:\n$name1\nwurde von $oldpreis€ auf $preis€ angepasst!";
							}
						}
					}
				}				
            }		
		}
	}
}

# ------------------------------------------------------------------------ #
# Preisvergleich Hilfe                                                     #
# ------------------------------------------------------------------------ #
sub getHelp($$)
{
    my ($dev,$id) = @_;
	fhem "set $dev message \@$id 	Hilfe Preisvergleich\n
									Wie lege ich einen neuen PVG an?\n
									1. PVG <Idealo-Link> <Preis[optional]>\n
									Oder\n
									2. Preisvergleich <Idealo-Link> <Preis[optional]>\n
									\n
									Wie sehe ich meine PVG?\n
									1. Meine PVG\n
									Oder\n
									2. Meine Preisvergleiche\n
									\n
									Wie starte / stoppe ich meine PVG?\n
									1. Start|Stop PVG\n
									Oder\n
									2. Start|Stop Preisvergleich\n
									\n
									Wie ändere ich bestehende Preiswecker?\n
									1. Ändere PVG <iPhone> <neuer_Preis>\n
									Oder\n
									2. Ändere Preisvergleich <iPhone> <neuer_Preis>\n
									\n
									Zeige mir den aktuellen Preis für einen bestehenden Preisvergleich?\n
									1. Aktueller PVG <iPhone>\n
									Oder\n
									2. Aktueller Preisvergleich <iPhone>\n
									\n									
									Wie lösche ich bestehende PVG?\n
									1. Lösche PVG <iPhone>\n
									Oder\n
									2. Lösche Preisvergleich <iPhone>";
}

1;