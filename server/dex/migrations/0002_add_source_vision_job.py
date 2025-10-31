# Generated migration for adding source_vision_job to DexEntry

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('dex', '0001_initial'),
        ('vision', '0002_add_dex_compatible_image_fields'),
    ]

    operations = [
        migrations.AddField(
            model_name='dexentry',
            name='source_vision_job',
            field=models.ForeignKey(
                blank=True,
                help_text='Source vision job with dex-compatible image',
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='dex_entries',
                to='vision.analysisjob'
            ),
        ),
    ]
