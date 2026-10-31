import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/utils/local_image_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('localImageWidget downsampling', () {
    testWidgets(
      'calculates effectiveCacheWidth and cacheHeight for finite dimensions',
      (tester) async {
        final widget = localImageWidget(
          'dummy_path.png',
          width: 150,
          height: 100,
        );

        expect(widget, isA<Image>());
        final image = widget as Image;
        expect(image.width, 150);
        expect(image.height, 100);

        // When cacheWidth/cacheHeight are passed to Image.file, it wraps the provider in ResizeImage
        expect(image.image, isA<ResizeImage>());
        final resizeImage = image.image as ResizeImage;
        expect(resizeImage.width, 450);
        expect(resizeImage.height, 300);
      },
    );

    testWidgets('respects explicit cacheWidth and cacheHeight if provided', (
      tester,
    ) async {
      final widget = localImageWidget(
        'dummy_path.png',
        width: 150,
        height: 100,
        cacheWidth: 200,
        cacheHeight: 150,
      );

      expect(widget, isA<Image>());
      final image = widget as Image;
      expect(image.image, isA<ResizeImage>());
      final resizeImage = image.image as ResizeImage;
      expect(resizeImage.width, 200);
      expect(resizeImage.height, 150);
    });

    testWidgets(
      'leaves provider unresized when width and height are unbounded (full size)',
      (tester) async {
        final widget = localImageWidget('dummy_path.png', fit: BoxFit.contain);

        expect(widget, isA<Image>());
        final image = widget as Image;
        // Since cacheWidth/cacheHeight are null, provider is FileImage directly
        expect(image.image, isA<FileImage>());
      },
    );
  });
}
