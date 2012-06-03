use XML::Simple;
use Data::Dumper;
use LWP::Simple;
use Time::localtime;
use strict;
use warnings;
 
my $app = sub {

my $env = shift;
# Date time------------
my $tm = localtime;
my $today=sprintf("%02d/%02d/%04d",($tm->mon)+1,$tm->mday,$tm->year+1900);
my $tomorrow=sprintf("%02d/%02d/%04d",($tm->mon)+1,$tm->mday+1,$tm->year+1900);
my $dayAfterTomorrow=sprintf("%02d/%02d/%04d",($tm->mon)+1,$tm->mday+2,$tm->year+1900);

my @channel = ("STAR Movies", "PIX","HBO", "ZStudio", "WB", "MGM", "TCM", "Movies Now");
my @channel1 = ("STAR Movies", "PIX","HBO", "ZStudio", "WB", "MGM", "TCM", "Movies Now");
my @channel2 = ("DD National", "StarPlus", "Life OK", "Imagine", "STAR Utsav", "Sony", "SAB", "Sahara One", "Zee TV", "UTV Bindass", "Colors");

my $lu;
if($env->{QUERY_STRING} eq '')
{
	$lu = $today;
}
else
{
	my @fi = split(/&/,$env->{QUERY_STRING});
	$lu = @fi[0];
	if(@fi[1] eq '2'){@channel = ("STAR Movies", "PIX","HBO", "ZStudio")}
	elsif(@fi[1] eq '3'){@channel = ("WB", "MGM", "TCM", "Movies Now")}
	elsif(!(@fi[1] eq '1')){@channel = @fi[1]}
}
my $xml = new XML::Simple;
my $data = get("http://tatasky.ryzmedia.com/v1.0/tv/fetch_daily_lineup.php?ID=1&Date=".$lu);

my $data1 = $data;
$data = $xml->XMLin($data);
$data1 =~ s/TMSId/name/g;
$data1 = $xml->XMLin($data1);
my $record = "'http://tatasky.ryzmedia.com/v1.0/booking/booking.php?UserId=5284047f-4ffb-3e04-824a-2fd1d1f0cd62&RequestId='+(Math.floor(Math.random()*9000000) + 1000000)
+'&SubId=1065302679&SourceId='+ id.split('-')[1].substring(0,id.split('-')[1].length-1) +'&EventId='+ id.split('-')[0]";
my $result = "<script language='javascript'>function r(id){window.open(".$record.");}<\/script>";
$result = $result."<a href='http://tv24-prafeb.dotcloud.com/?".$today."'>Today<a/>"." <a href='http://tv24-prafeb.dotcloud.com/?".$tomorrow."'>Tomorrow<a/>"." <a href='http://tv24-prafeb.dotcloud.com/?".$dayAfterTomorrow."'>Day After Tomorrow<a/><br/><br/>";

foreach(@channel1)
{
	$result = $result."<a href='http://tv24-prafeb.dotcloud.com/?".$lu."&".$_."'>".$_."</a>";
}

$result = $result."<br/>";
my $result2;
foreach(@channel)
{
	for my $item (@{$data->{lineup}->{channel}->{$_}->{schedule}})
	{
		my $name = $data1->{programs}->{program}->{$item->{TMSId}}->{shortName};		
		my $ht = get("http://www.imdbapi.com/?i=&t=".$name);
		#my $ht = get("http://www.deanclatworthy.com/imdb/?q=".$name);
		my @fi = split(/"Rating":"/,$ht);
		my @fi1 = split(/","Votes"/,@fi[1]);	
#		if (index($ht, "Service Unavailable") == -1)
#		{
#			$ht = get("http://www.deanclatworthy.com/imdb/?q=".$name);
#			@fi = split(/"rating":"/,$ht);
#			@fi1 = split(/","runtime"/,@fi[1]);	
#		}		
		$ht =~ 	s/"|'//g;
		$ht =~ 	s/,/\\n/g;
		if(@fi1[0] eq "" || @fi1[0] eq "N/A"){@fi1[0]="0.0";}	
		my $desc = $data1->{programs}->{program}->{$item->{TMSId}}->{desc};
		$desc =~ s/"|'//g;
		$result2 = $result2.@fi1[0]."  ".$item->{Time}."  <a onclick='alert(\"".$desc."\")'>".$name."</a>  ".$_." <a onclick=\"r('".$item->{TMSId}."')\">&reg;<a/><br/>";
	}
}
	
foreach(@channel2)
{
	for my $item (@{$data->{lineup}->{channel}->{$_}->{schedule}})
	{
		my $name = $data1->{programs}->{program}->{$item->{TMSId}}->{shortName};				
		if($name =~ m/Movie -/)		
		{
				
				my $desc = $data1->{programs}->{program}->{$item->{TMSId}}->{desc};
				$desc =~ s/"|'//g;
my $time = $result2.$item->{Time};
my (@timea) = ($time =~ m/(\d+):(\d+):(\d+)/);
				
#$hours = $hours + 5;
				$result2 = $time." ".@timea[0]."  <a onclick='alert(\"".$desc."\")'>".$name."</a>  ".$_." <a onclick=\"r('".$item->{TMSId}."')\">&reg;<a/><br/>";
	
		}
	}
}
my @fi = split(/<br\/>/,$result2);
			@fi = reverse sort(@fi);
			my $itm = "";
			foreach(@fi)
			{					
				$itm = $itm.$_."<br/>";				
			}		
    return [200, ['Content-Type' => 'text/html'], [$result.$itm]];
}
