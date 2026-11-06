package io.github.m4hdhi.keepgreen.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.m4hdhi.keepgreen.remote.StatusTone
import io.github.m4hdhi.keepgreen.ui.theme.StatusColors

/** Green for Active, grey for Disabled, amber for everything else, as on the desktop. */
fun StatusTone.color(): Color = when (this) {
    StatusTone.Active -> StatusColors.Active
    StatusTone.Disabled -> StatusColors.Disabled
    StatusTone.Paused -> StatusColors.Attention
}

/** The rounded card every section sits on. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SectionCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(20.dp)
    val colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    val border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    if (onClick == null) {
        Card(modifier = modifier.fillMaxWidth(), shape = shape, colors = colors, border = border, content = content)
    } else {
        Card(onClick = onClick, modifier = modifier.fillMaxWidth(), shape = shape, colors = colors, border = border, content = content)
    }
}

/** An icon and a bold title above a card's content. */
@Composable
fun SectionHeader(icon: ImageVector, title: String, modifier: Modifier = Modifier) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(title, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
fun StatusDot(color: Color, modifier: Modifier = Modifier, size: Dp = 12.dp) {
    Box(modifier.size(size).background(color, CircleShape))
}

/**
 * The big status circle from the desktop dashboard. While [pulsing], a soft ring grows out of it
 * and fades, like the desktop's breathing halo.
 */
@Composable
fun StatusOrb(
    color: Color,
    icon: ImageVector,
    pulsing: Boolean,
    modifier: Modifier = Modifier,
    size: Dp = 120.dp,
) {
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        if (pulsing) {
            val transition = rememberInfiniteTransition(label = "orb")
            val progress by transition.animateFloat(
                initialValue = 0f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(tween(durationMillis = 2000, easing = LinearEasing), RepeatMode.Restart),
                label = "halo",
            )
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        val scale = 0.55f + 0.45f * progress
                        scaleX = scale
                        scaleY = scale
                        alpha = 0.5f * (1f - progress)
                    }
                    .background(color, CircleShape),
            )
        }
        Box(
            Modifier
                .size(size * 0.56f)
                .background(color, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(size * 0.26f))
        }
    }
}

/** A small labelled number, like the desktop's stat cards. */
@Composable
fun StatTile(label: String, value: String, caption: String, modifier: Modifier = Modifier) {
    Column(modifier.padding(vertical = 4.dp)) {
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 4.dp, bottom = 2.dp))
        Text(caption, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
