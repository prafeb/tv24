#!/usr/local/bin/perl
use warnings;
use utf8;

use Mojolicious::Lite;
use Mojo::JSON;

use DBI qw(:sql_types);
use HTML::Table::FromDatabase;
use HTML::Table;
use DateTime;
use DateTime::Format::Strptime;
use XML::Simple;
use Data::Dumper;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new;
$ua->agent("MyApp/0.1 ");
my $json   = Mojo::JSON->new;
my $hash;

my $dbh = DBI->connect( "DBI:SQLite:dbname=test.db", "", "", 
{ RaiseError => 1, AutoCommit => 1, sqlite_unicode => 1 } ) or die $DBI::errstr;
$dbh->do("PRAGMA cache_size = 400000");
$dbh->do("PRAGMA synchronous = OFF");

get '/setup' => sub {
	my $self = shift;
	$dbh->do("CREATE TABLE channel(id INTEGER PRIMARY KEY, name TEXT)");
	$dbh->do("CREATE TABLE movie(id INTEGER PRIMARY KEY, name TEXT, rating REAL, plot TEXT, genre TEXT, director TEXT, writer TEXT, actor TEXT, poster TEXT, runtime TEXT, year TEXT, rated TEXT, released TEXT, votes TEXT)");
	$dbh->do("CREATE TABLE program(id INTEGER PRIMARY KEY, datetime TEXT, channelid int, movieid int)");
	$dbh->do("CREATE TABLE recorded(userid INTEGER, movieid INTEGER, status int)");
	$dbh->do("CREATE TABLE exception(userid INTEGER, movieid INTEGER)");
	$dbh->do("CREATE TABLE user(id INTEGER, username TEXT, password TEXT, email TEXT, firstname TEXT, lastname TEXT)");

	$self->render_text('Done');
};

get '/addchannel/:cn' => sub{
    	my $self = shift;
	$dbh->do("INSERT INTO channel VALUES (NULL, '".$self->param('cn')."')");
	$self->render_text($self->param('cn').' added');
};
get '/addexception/:userid/:movieid' => sub{
    	my $self = shift;
	$dbh->do("INSERT INTO exception VALUES (1,".$self->param('movieid').")");
	$self->render_text('added');
};
get '/delete/:entity/:condition' => sub{
    	my $self = shift;	
	$dbh->do("delete from ".$self->param('entity')." where ".$self->param('condition'));
	$self->render_text('Done');
};

get '/sync' => sub {
    	my $self = shift;
	for(my $i = 0; $i < 1; $i++)
	{
		&syncProgram(DateTime->today()->add(days => $i));
	}
	$self->render_text('Done');
};

sub syncProgram
{
	my $format = new DateTime::Format::Strptime(pattern => '%d-%m-%Y %H:%M:%S',time_zone => 'GMT',);
	my $xml = new XML::Simple;

	#open FILE, "<data1.xml";
	#my $data = do { local $/; <FILE> };
	my $data = &getHTML("http://tatasky.ryzmedia.com/v1.0/tv/fetch_daily_lineup.php?ID=1&Date=".$_[0]->strftime("%m/%d/%Y"));
    	
	my $sth = $dbh->prepare( "SELECT id, name FROM channel" );
	$sth->execute();
	my $sth1 = $dbh->prepare( q/SELECT id FROM movie where name = ?/);
	my $data1 = $data;
	$data = $xml->XMLin($data);
	$data1 =~ s/TMSId/name/g;
	$data1 = $xml->XMLin($data1);

	
	# Create local hash to prevent duplicate entry in program table
	my $program =  $dbh->prepare( q/SELECT datetime||'-'||channelid||'-'||movieid FROM program/);
	$program->execute();
	my %programhash;

	while (my @fields = $program->fetchrow_array()) 
	{  
		$programhash{$fields[0]} = $fields[0];		
	}	
	#################
	while ( (my @channel) = $sth->fetchrow_array() ) 
	{
		for my $item (@{$data->{lineup}->{channel}->{$channel[1]}->{schedule}})
		{
			my $name = $data1->{programs}->{program}->{$item->{TMSId}}->{shortName};
			my $desc = $data1->{programs}->{program}->{$item->{TMSId}}->{desc};
			$name =~ s/'/''/g;
			$desc =~ s/'/''/g;
			my $programDateTime = $format->parse_datetime($_[0]->strftime("%d-%m-%Y ").$item->{Time});
			$programDateTime->add( hours => 5, minutes => 7 );
			
			$sth1->execute(($name));
			my @row = $sth1->fetchrow_array;
			if($#row + 1 == 0)
			{
				my $result = &getHTML("http://www.imdbapi.com/?i=&t=".$name);
 				$result =~ s/'/''/g;				
				$hash = $json->decode($result);				
				if($hash->{'imdbRating'} eq "" || $hash->{'imdbRating'} eq "N/A"){$hash->{'imdbRating'}="0.0";}					
				$dbh->do(sprintf "INSERT INTO movie VALUES (NULL, '%s', %s, '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s')"
					, $name, $hash->{'imdbRating'}, $desc."<br/><br/>IMDB:<br/>".$hash->{'Plot'}, $hash->{'Genre'}, $hash->{'Year'}
					, $hash->{'Rated'}, $hash->{'Released'}, $hash->{'Director'}, $hash->{'Writer'}, $hash->{'Actors'}
					, $hash->{'Poster'}, $hash->{'Runtime'}, $hash->{'imdbVotes'});
				$sth1->execute(($name));
				@row = $sth1->fetchrow_array;
			}
			
			if(! exists $programhash{$programDateTime->strftime("%Y-%m-%d %H:%M")."-".$channel[0]."-".$row[0]})
			{			
				$dbh->do("INSERT INTO program VALUES (NULL, '".$programDateTime->strftime("%Y-%m-%d %H:%M")."', ".$channel[0].", ".$row[0].")");			
			}
			
		}
	}
	undef %programhash;
	# delete old progam table entries
#	$program =  $dbh->prepare( q/delete FROM program where datetime < ?/);
#	$program->execute((DateTime->now()->add( hours => 5.5)->strftime("%Y-%m-%d %H:%M")));
	$sth->finish();	
}
sub getHTML
{
	# Create a request
	my $req = HTTP::Request->new(GET => $_[0]);
	$req->content_type('application/x-www-form-urlencoded');
	$req->content('query=libwww-perl&mode=dist');

	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);

	# Check the outcome of the response
	$res->decoded_content if $res->is_success;	
}

get '/index' => sub {
	my $self = shift;
	my $table;

	# prepare program table
	my $sth = $dbh->prepare( "SELECT b.rating, a.datetime, b.name, d.name, b.year, b.genre, b.Votes, b.plot, b.poster  FROM program a 
		join movie b on a.movieid = b.id 
		left join exception c on b.id = c.movieid and c.userid = 1
		join channel d on d.id = a.channelid 
		where c.movieid is null and datetime > '".DateTime->now()->add( hours => 5.5)->strftime("%Y-%m-%d %H:%M")."' order by datetime desc" );

	$sth->execute();
	$table = "<table id='tableprogram' class='tablesorter' border=0 cellpadding=0 cellspacing=1>
			<thead>
				<tr>
					<th>$sth->{NAME}->[0]</th>
					<th>$sth->{NAME}->[1]</th>
					<th>$sth->{NAME}->[2]</th>
					<th>$sth->{NAME}->[3]</th>
					<th>$sth->{NAME}->[4]</th>
					<th>$sth->{NAME}->[5]</th>
					<th>$sth->{NAME}->[6]</th>
					<th>$sth->{NAME}->[7]</th>
					<th>$sth->{NAME}->[8]</th>										
				</tr>
			</thead>
			<tbody>";
	my $format = new DateTime::Format::Strptime(pattern => '%Y-%m-%d %H:%M',time_zone => 'GMT',);

	while ( (my @programRow) = $sth->fetchrow_array() ) 
	{
		$table = $table."<tr>
					<td>$programRow[0]</td>
					<td>".$format->parse_datetime($programRow[1])->strftime("%Y-%m-%d %H:%M (%l:%M %p)")."</td>
					<td>$programRow[2]</td>
					<td>$programRow[3]</td>
					<td>$programRow[4]</td>
					<td>$programRow[5]</td>
					<td>$programRow[6]</td>
					<td>$programRow[7]</td>
					<td>$programRow[8]</td>
				</tr>";
	}
	$table = $table."</tbody></table>";
	
	$self->stash( program => $table );

    	$self->render( 'index' );

};

#sub sub1
#{
#	my $sth = $dbh->prepare( $_[0] );
#	$sth->execute();
#	my $t = HTML::Table::FromDatabase->new( -sth => $sth, -border => 0 , -class => 'tablesorter', transform => sub { $_ = shift; qq[<a href="$_">$_</a>];, -id=>'tablesorter-demo', -padding=>0, -spacing=>1);
#	$_[1] = $t->getTable();
#};
app->start;

__DATA__
@@ index.html.ep
<!doctype html>
<html>
<head><title>Test</title><meta charset="UTF-8">
<link rel="stylesheet" href="style.css" type="text/css" >
	<script type="text/javascript" src="jquery-latest.js"></script>
	<script type="text/javascript" src="__jquery.js"></script>
	<script type="text/javascript">
	$(function() {$("#tableprogram").tablesorter({sortList:[[0,1]]});});	
	</script>
</head>
<body>
<%== $program%>
</body>
</html>

@@ error.html.ep
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html;charset=UTF-8" >
    <title>Error</title>
  </head>
  <body>
    <%= $message %>
  </body>
</html>

