import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/modules/settings/providers/app_settings.provider.dart';
import 'package:immich_mobile/modules/settings/services/app_settings.service.dart';

enum AssetsInTimeline { selected, excluded, all, none }

class AssetListMainTimelineSetting extends ConsumerWidget {
  const AssetListMainTimelineSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localAssetsInTimeline = AssetsInTimeline.values[ref.watch(
      appSettingsServiceProvider.select(
        (value) => value.getSetting(AppSettingsEnum.localAssetsInMainTimeline),
      ),
    )];

    void changeGroupValue(AssetsInTimeline? value) {
      if (value != null) {
        ref.read(appSettingsServiceProvider).setSetting(
              AppSettingsEnum.localAssetsInMainTimeline,
              value.index,
            );
      }
      ref.invalidate(appSettingsServiceProvider);
    }

    return Column(
      children: [
        const Divider(
          indent: 18,
          endIndent: 18,
        ),
        ListTile(
          title: const Text(
            "asset_list_main_timeline_title",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ).tr(),
        ),
        RadioListTile<AssetsInTimeline>(
          activeColor: context.primaryColor,
          title: Text(
            "asset_list_main_timeline_selected",
            style: context.textTheme.labelLarge,
          ).tr(),
          value: AssetsInTimeline.selected,
          groupValue: localAssetsInTimeline,
          onChanged: changeGroupValue,
          controlAffinity: ListTileControlAffinity.trailing,
        ),
        RadioListTile<AssetsInTimeline>(
          activeColor: context.primaryColor,
          title: Text(
            "asset_list_main_timeline_all",
            style: context.textTheme.labelLarge,
          ).tr(),
          value: AssetsInTimeline.all,
          groupValue: localAssetsInTimeline,
          onChanged: changeGroupValue,
          controlAffinity: ListTileControlAffinity.trailing,
        ),
        RadioListTile<AssetsInTimeline>(
          activeColor: context.primaryColor,
          title: Text(
            "asset_list_main_timeline_none",
            style: context.textTheme.labelLarge,
          ).tr(),
          value: AssetsInTimeline.none,
          groupValue: localAssetsInTimeline,
          onChanged: changeGroupValue,
          controlAffinity: ListTileControlAffinity.trailing,
        ),
      ],
    );
  }
}
