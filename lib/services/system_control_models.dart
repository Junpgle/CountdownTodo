/// 媒体播放状态。
enum PlaybackStatus { playing, paused, stopped, unknown }

/// 当前正在播放的媒体信息。
class MediaInfo {
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final PlaybackStatus status;

  const MediaInfo({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.albumArtist = '',
    this.status = PlaybackStatus.unknown,
  });

  bool get isEmpty => title.isEmpty && artist.isEmpty;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MediaInfo &&
            title == other.title &&
            artist == other.artist &&
            album == other.album &&
            albumArtist == other.albumArtist &&
            status == other.status;
  }

  @override
  int get hashCode => Object.hash(title, artist, album, albumArtist, status);

  @override
  String toString() =>
      'MediaInfo(title: "$title", artist: "$artist", '
      'album: "$album", albumArtist: "$albumArtist", status: $status)';
}
